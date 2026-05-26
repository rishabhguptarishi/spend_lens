# frozen_string_literal: true

# Phase 6 §"Admin parser-coverage metrics" — print parser health.
#
# Usage:
#   rake parser:coverage                 # human-readable summary
#   rake parser:coverage FORMAT=json     # machine-readable JSON
#   rake parser:coverage USER_ID=42      # restrict to one user
#
# Reports on each statement parsed since Phase 3 stamped parser_name +
# parse_quality on the Statement row. Aggregates: which fingerprints
# matched (vs falling through to GenericParser), balance-verification
# success rate, and AI-merge usage rate.
namespace :parser do
  desc "Print bank parser coverage and balance-verification stats"
  task coverage: :environment do
    scope = Statement.where.not(parser_name: nil)
    if (user_id = ENV['USER_ID'])
      scope = scope.joins(:bank_account).where(bank_accounts: { user_id: user_id.to_i })
    end

    stats = build_stats(scope)

    if ENV['FORMAT'] == 'json'
      require 'json'
      puts JSON.pretty_generate(stats)
    else
      print_human_summary(stats)
    end
  end

  def build_stats(scope)
    total = scope.count
    by_parser = scope.group(:parser_name, :parser_version).count

    rows = by_parser.map do |(parser, version), count|
      sub = scope.where(parser_name: parser, parser_version: version)
      verified = sub.where("parse_quality ->> 'verified' = 'true'").count
      failed_check = sub.where("parse_quality ->> 'verified' = 'false'").count
      ai_used = sub.where("parse_quality ->> 'ai_used' = 'true'").count

      {
        parser: parser,
        version: version,
        statements: count,
        balance_verified: verified,
        balance_failed_check: failed_check,
        balance_unknown: count - verified - failed_check,
        ai_assisted: ai_used,
        balance_verified_pct: count.positive? ? ((verified.to_f / count) * 100).round(1) : 0.0,
      }
    end.sort_by { |r| -r[:statements] }

    {
      total_statements_parsed: total,
      generic_fallback_count: rows.find { |r| r[:parser] == StatementParsing::Banks::GenericParser.bank_name }&.dig(:statements) || 0,
      generic_fallback_pct: total.positive? ? ((rows.find { |r| r[:parser] == StatementParsing::Banks::GenericParser.bank_name }&.dig(:statements).to_f / total) * 100).round(1) : 0.0,
      by_parser: rows,
      registered_parsers: StatementParsing::BankFingerprintRegistry.all.map { |e| { name: e.name, version: e.parser::VERSION, features: e.features } },
    }
  end

  def print_human_summary(stats)
    puts "\n=== SpendLens parser coverage ==="
    puts "Total parsed statements: #{stats[:total_statements_parsed]}"
    puts "Generic fallback: #{stats[:generic_fallback_count]} (#{stats[:generic_fallback_pct]}%)"
    puts ""
    puts "%-12s %-10s %10s %10s %10s %10s" % %w[parser version count verified% ai-used failed-check]
    puts "-" * 72
    stats[:by_parser].each do |r|
      puts "%-12s %-10s %10d %9.1f%% %10d %10d" % [r[:parser], r[:version], r[:statements], r[:balance_verified_pct], r[:ai_assisted], r[:balance_failed_check]]
    end

    puts "\nRegistered parsers:"
    stats[:registered_parsers].each do |p|
      puts "  - #{p[:name]} v#{p[:version]} (#{Array(p[:features]).join(', ')})"
    end
    puts ""
  end
end
