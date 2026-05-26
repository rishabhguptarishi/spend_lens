# frozen_string_literal: true

module Ai
  module Tools
    # Central tool registry. Filter by mode to control which tools the LLM sees.
    class Registry
      SPENDING_READ = [
        SearchTransactions,
        MonthlySummary,
        TopMerchants,
        RecurringTransactions,
        CreditCardSummary,
        BestCardForPurchase,
        BudgetStatus,
        NetWorth,
        HoldingsSnapshot,
        ListCategories,
        UncategorizedTransactions,
      ].freeze

      SPENDING_WRITE = [
        ProposeRecategorize,
        ProposeCreateBudget,
        ProposeCreateCategoryRule,
        ProposeCreateCategory,
      ].freeze

      ITR_READ = [
        ItrReadiness,
        TaxSavings,
        AisReconciliation,
        RegimeCompare,
        CapitalGains,
        SearchTransactions,
        HoldingsSnapshot,
      ].freeze

      def self.for(mode:, allow_writes: true)
        case mode.to_s
        when 'itr'
          ITR_READ
        else
          allow_writes ? SPENDING_READ + SPENDING_WRITE : SPENDING_READ
        end
      end

      def self.declarations(tools)
        tools.map(&:declaration)
      end

      def self.find(tools, name)
        tools.find { |t| t.tool_name == name.to_s }
      end
    end
  end
end
