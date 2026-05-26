# frozen_string_literal: true

# Phase 1, Migration B: identity_key on investment_holdings.
#
# A canonical, cross-source identifier for a real-world security/account:
#   stock/mf/bond/sgb/reit/invit:   ISIN where present, fallback to ticker
#   fd/rd:                          "FD:<bank>:<deposit_no>"
#   ppf/sukanya:                    "PPF:<bank>:<account_no>"
#   nps:                            "NPS:<pran>"
#   epf:                            "EPF:<uan>"
#   rsu/espp/esop:                  "<kind>:<company>:<grant_id>"
#   p2p / fractional_re / crypto:   platform-scoped composite key
#
# A partial unique index on (user_id, identity_key) WHERE identity_key
# IS NOT NULL means we get true cross-source dedup for any holding that
# has enough metadata to compute a key, while legacy rows (and types
# with no canonical key like manual real_estate) continue working.
class AddIdentityKeyToInvestmentHoldings < ActiveRecord::Migration[8.0]
  def change
    add_column :investment_holdings, :identity_key, :string

    add_index :investment_holdings, %i[user_id identity_key],
      unique: true,
      where: 'identity_key IS NOT NULL',
      name: 'index_investment_holdings_on_user_identity_key'
  end
end
