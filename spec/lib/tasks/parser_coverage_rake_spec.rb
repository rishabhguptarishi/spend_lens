# frozen_string_literal: true

require "rails_helper"
require "rake"

# Phase 6: rake parser:coverage prints a summary of bank-parser usage.
RSpec.describe "parser:coverage rake task" do
  before(:all) do
    Rails.application.load_tasks unless Rake::Task.task_defined?("parser:coverage")
  end

  before(:each) do
    Rake::Task["parser:coverage"].reenable
  end

  let(:user) { make_user }
  let(:bank) { make_bank_account(user: user) }

  it "runs without error when there are no parsed statements" do
    expect { Rake::Task["parser:coverage"].invoke }.to output(/Total parsed statements: 0/).to_stdout
  end

  it "aggregates stats by parser name + version" do
    make_statement(bank_account: bank, status: "parsed", parser_name: "hdfc", parser_version: "1.0", parse_quality: { "verified" => true, "ai_used" => false })
    make_statement(bank_account: bank, status: "parsed", parser_name: "hdfc", parser_version: "1.0", parse_quality: { "verified" => false, "ai_used" => true })
    make_statement(bank_account: bank, status: "parsed", parser_name: "generic", parser_version: "1.0", parse_quality: { "verified" => true })

    expect { Rake::Task["parser:coverage"].invoke }.to output(/hdfc/).to_stdout
  end

  it "supports FORMAT=json" do
    make_statement(bank_account: bank, status: "parsed", parser_name: "icici", parser_version: "1.0", parse_quality: { "verified" => true })

    ENV["FORMAT"] = "json"
    expect { Rake::Task["parser:coverage"].invoke }.to output(/"total_statements_parsed":\s*1/).to_stdout
  ensure
    ENV.delete("FORMAT")
  end
end
