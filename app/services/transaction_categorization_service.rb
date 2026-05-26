# frozen_string_literal: true

# Categorizes transactions using: 1) user's learned rules, 2) Indian bank-code shortcuts,
# 3) AI (creates new categories if needed), 4) generic keyword fallback.
class TransactionCategorizationService
  # Indian bank statements lean heavily on cryptic 2-5 letter codes
  # (MOB-TD, FRSB, ACH-CR, NACH-DR, AUTOSWEEP, ...). AI consistently
  # misroutes these — e.g. "MOB-TD/926040058278575/RISHABH GUPTA" reads
  # like a peer transfer to AI because of the customer-name suffix, even
  # though MOB-TD unambiguously means "Mobile-banking Term Deposit" (an
  # FD action). These rules win BEFORE the AI call so we never waste a
  # round-trip on patterns whose meaning is fixed by banking convention.
  #
  # Ordering matters: more specific patterns must come before generic
  # NEFT/IMPS/UPI fallbacks.
  BANK_CODE_RULES = [
    # ---- Investments: FD / RD / sweeps ----
    [/\bMOB[-\s]?TD\b/i,                                 'Investments'],   # Mobile Term Deposit
    [/\bMOB[-\s]?FD\b/i,                                 'Investments'],   # Mobile Fixed Deposit
    [/\bMOB[-\s]?RD\b/i,                                 'Investments'],   # Mobile Recurring Deposit
    [/\bAUTOSWEEP\b/i,                                   'Investments'],   # Sweep into linked FD
    [/\bREV\s+SWEEP\b/i,                                 'Investments'],   # Reverse sweep from FD
    [/\bSWEEP\s+TRF\b/i,                                 'Investments'],   # Sweep transfer (FD-linked)
    [/\bFRSB\b/i,                                        'Investments'],   # RBI Floating Rate Savings Bond (7.15% gov bond)

    # ---- Investments: brokers & SIPs ----
    [/\bAXISDIRECT\b/i,                                  'Investments'],
    [/\b(?:ZERODHA|KITE)\b/i,                            'Investments'],
    [/\bGROWW\b/i,                                       'Investments'],
    [/\bUPSTOX\b/i,                                      'Investments'],
    [/\bINDMONEY|IND\s*MONEY\b/i,                        'Investments'],
    [/\b(?:CANARA\s+ROBECO|MIRAE\s+ASSET|NIPPON\s+(?:LIFE|INDIA)|SBI\s+MF|HDFC\s+MF|ICICI\s+PRU|AXIS\s+(?:MF|SMALL\s+CAP)|KOTAK\s+MF|UTI\s+MF|PARAG\s+PARIKH|MOTILAL\s+OSWAL|QUANT\s+MF)\b/i, 'Investments'],

    # ---- Income ----
    [/\bACH[-\s]CR\b/i,                                  'Income'],        # NACH credit (often dividend)
    [/\bInt\.Pd\b/i,                                     'Interest Income'],
    [/\b(?:NEFT|RTGS|IMPS)\s+CR\b/i,                     'Income'],
    [/\b(?:SALARY|SAL\s+CR)\b/i,                         'Income'],

    # ---- Bills / Utilities (NACH debits are usually SIPs OR utilities;
    # treat as "Bills" only when paired with a generic merchant tag) ----
    [/\bECS\s+DR\b/i,                                    'Bills'],

    # ---- Loan EMIs ----
    [/\b(?:EMI|LOAN\s+EMI|HOUSING\s+LOAN|HOME\s+LOAN)\b/i, 'EMI'],
  ].freeze

  # Fallback when Ollama is unavailable (and the bank-code rules above
  # don't match)
  MERCHANT_KEYWORDS = {
    'Food & Dining' => %w[swiggy blinkit zomato dominos mcdonalds kfc pizza hut foodpanda dunzo bigbasket instamart],
    'Entertainment' => %w[netflix spotify amazon prime hotstar disney+ youtube premium bookmyshow],
    'Transport' => %w[ola uber rapido irctc petrol pump fuel],
    'Shopping' => %w[amazon flipkart myntra ajio meesho],
    'Utilities' => %w[electricity water gas broadband recharge airtel jio vi],
    'Healthcare' => %w[pharmacy apollo medanta hospital doctor],
    'Travel' => %w[booking makemytrip goibibo oyo],
    'Transfer' => %w[imps neft rtgs upi transfer paytm gpay],
  }.freeze

  def initialize(user)
    @user = user
    @prefs = UserPreference.new(user)
  end

  def categorize(description, merchant: nil)
    text = [description, merchant].compact.join(' ').strip
    return uncategorized if text.blank?

    # 1. User's learned rules (from corrections) - explicit user preferences
    matching_rules = user_rules.select { |r| r.matches?(text.downcase) }
    best = matching_rules.max_by { |r| r.merchant_pattern.length }
    return best.category if best

    unless @prefs.auto_categorize_statements?
      return default_category || uncategorized
    end

    # 2. Indian bank-code shortcuts. These are deterministic (MOB-TD is
    #    *always* a term deposit) so we resolve them before paying the
    #    cost of an AI call — and we sidestep AI's habit of routing
    #    "MOB-TD/.../RISHABH GUPTA" to Transfer because of the trailing
    #    customer name.
    bank_code_category = categorize_by_bank_code(text)
    return bank_code_category if bank_code_category

    # 3. AI categorization first - creates new category if AI suggests one we don't have
    ai_category = categorize_with_ai(text) if @prefs.ai_categorize?
    return ai_category if ai_category

    # 4. Keyword fallback (only when Ollama is down)
    keyword_category = categorize_by_keywords(text.downcase)
    return keyword_category if keyword_category

    # 5. Default
    default_category || uncategorized
  end

  # Call when user corrects a category - learn from it
  def learn(description, merchant: nil, category:)
    text = [description, merchant].compact.join(' ').strip
    return if text.blank?

    # Extract a stable merchant pattern (e.g. "SWIGGY" from "SWIGGY INDIA PVT LTD")
    pattern = extract_merchant_pattern(text)
    return if pattern.blank? || pattern.length < 3

    rule = @user.category_rules.find_or_initialize_by(merchant_pattern: pattern.downcase)
    rule.category = category
    rule.save!
  end

  private

  # ------------------------------------------------------------------
  # Per-instance caches. Persister creates one categorizer per statement,
  # so memoizing here turns ~3 queries per transaction (rules / category
  # names / category lookup) into ~3 queries per *statement*.
  # ------------------------------------------------------------------

  def user_rules
    @user_rules ||= @user.category_rules.includes(:category).to_a
  end

  def categories_by_lower_name
    @categories_by_lower_name ||= @user.categories.each_with_object({}) do |c, h|
      h[c.name.to_s.downcase] = c
    end
  end

  def find_category_by_name(name)
    categories_by_lower_name[name.to_s.downcase]
  end

  def existing_category_names_csv
    @existing_category_names_csv ||= categories_by_lower_name.values.map(&:name).join(', ')
  end

  # When a new category is created mid-statement, update the cache so the next
  # transaction in the same batch sees it.
  def remember_category(cat)
    return cat unless cat

    categories_by_lower_name[cat.name.to_s.downcase] = cat
    @existing_category_names_csv = nil
    cat
  end

  def categorize_by_keywords(text)
    MERCHANT_KEYWORDS.each do |category_name, keywords|
      next unless keywords.any? { |kw| text.include?(kw) }

      cat = find_category_by_name(category_name)
      return cat if cat
    end
    nil
  end

  # Resolves the BANK_CODE_RULES regex list. When a rule matches we
  # return the user's existing category by that name; if the user
  # doesn't have it yet AND ai_create_categories? is on, we create it.
  # Otherwise we return nil and let AI / fallback take over.
  def categorize_by_bank_code(text)
    BANK_CODE_RULES.each do |re, category_name|
      next unless text.match?(re)

      if (existing = find_category_by_name(category_name))
        return existing
      end

      next unless @prefs.ai_create_categories?

      return remember_category(@user.categories.create!(name: category_name, color: random_category_color))
    end
    nil
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.warn "Bank-code category create failed: #{e.message}"
    nil
  end

  def uncategorized
    find_category_by_name('uncategorized') ||
      remember_category(@user.categories.create!(name: 'Uncategorized', color: '#94a3b8'))
  end

  def categorize_with_ai(text)
    return nil if text.blank? || !@prefs.ai_categorize?

    prompt = <<~PROMPT
      Categorize this Indian bank transaction. Return ONLY one category name, nothing else.

      Existing categories (prefer these): #{existing_category_names_csv}
      If none fit, suggest a new one (e.g. Subscriptions, Education, Insurance).

      Glossary of common Indian bank-statement codes (use these meanings
      rather than guessing from any customer name in the description):
      - MOB-TD / MOB-FD / MOB-RD: Mobile-banking term / fixed / recurring deposit → Investments
      - AUTOSWEEP / REV SWEEP / SWEEP TRF: sweep between savings and linked FD → Investments
      - FRSB: RBI Floating Rate Savings Bond (7.15% government bond) subscription or redemption → Investments
      - AXISDIRECT / ZERODHA / KITE / GROWW / UPSTOX / INDMONEY: stock-broker fund flow → Investments
      - Mutual-fund AMC names (Canara Robeco, MIRAE ASSET, Nippon India, SBI MF, HDFC MF, ICICI Pru, Parag Parikh, etc.): MF SIP → Investments
      - ACH-CR + a company name: NACH credit, typically a dividend payout → Income
      - Int.Pd or "Interest Paid": quarterly SB interest credit → Interest Income
      - NEFT/IMPS/UPI/RTGS preceded or followed by a person's name but no bank code: peer-to-peer transfer → Transfer
      - SALARY / SAL CR: monthly salary → Income
      - EMI / Loan EMI: loan repayment → EMI

      A customer-name suffix (like "/RISHABH GUPTA") does NOT make a
      transaction a peer transfer — always read the leading code first.

      Transaction: #{text.truncate(200)}

      Category:
    PROMPT

    response = call_ollama(prompt)
    return nil if response.blank?

    name = response.strip.gsub(/[^\w\s&\-\']/, '').strip
    return nil if name.length < 2
    return nil if name.downcase == 'uncategorized'

    cat = find_category_by_name(name)
    return cat if cat

    return nil unless @prefs.ai_create_categories?

    remember_category(@user.categories.create!(name: name.titleize, color: random_category_color))
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.warn "AI category create failed: #{e.message}"
    find_category_by_name(name.to_s)
  rescue => e
    Rails.logger.warn "AI categorization failed: #{e.message}"
    nil
  end

  # Palette of distinct colors. Picks one not already used by user's categories.
  CATEGORY_COLOR_PALETTE = %w[
    #F59E0B #3B82F6 #8B5CF6 #10B981 #EC4899 #EF4444 #06B6D4 #6B7280
    #22c55e #84cc16 #f97316 #14b8a6 #a855f7 #e11d48 #0ea5e9 #64748b
  ].freeze

  def random_category_color
    used = categories_by_lower_name.values
      .map { |c| c.color.to_s.downcase.strip }
      .reject(&:blank?)
      .uniq
    available = CATEGORY_COLOR_PALETTE.map { |c| c.downcase.strip } - used
    return available.sample if available.any?

    # All palette colors used - generate a random distinct hue
    "##{format('%06x', rand(0x333333..0xCCCCCC))}"
  end

  def default_category
    id = @prefs.get('default_category_id')
    return nil if id.blank?

    @default_category ||= categories_by_lower_name.values.find { |c| c.id == id.to_i } ||
                          @user.categories.find_by(id: id)
  end

  def call_ollama(prompt)
    AiClient.chat(prompt, @prefs, temperature: 0.3)
  rescue => e
    Rails.logger.warn "AI categorization failed: #{e.message}"
    nil
  end

  def extract_merchant_pattern(text)
    # Take first 2-3 words or first meaningful token (e.g. "SWIGGY", "NETFLIX")
    words = text.to_s.split(/\s+/).reject { |w| w.length < 2 }
    return words.first&.gsub(/[^\w]/, '') if words.one?

    # Prefer all-caps or capitalized words (often merchant names)
    merchant = words.find { |w| w == w.upcase && w.length >= 4 } ||
               words.find { |w| w[0] == w[0].upcase && w.length >= 4 } ||
               words.first
    merchant.to_s.gsub(/[^\w]/, '')[0..30]
  end
end
