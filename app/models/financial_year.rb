# frozen_string_literal: true

# Indian financial year: 1 Apr – 31 Mar (FY labelled by start year, e.g. 2025 = FY 2025-26).
class FinancialYear
  def self.start_year_for(date)
    d = date.to_date
    d.month >= 4 ? d.year : d.year - 1
  end

  def self.range_for(start_year)
    start_year = start_year.to_i
    Date.new(start_year, 4, 1)..Date.new(start_year + 1, 3, 31)
  end

  def self.label(start_year)
    y = start_year.to_i
    format('%d-%02d', y, (y + 1) % 100)
  end

  def self.current_start_year
    start_year_for(Date.current)
  end

  def self.available_years(count: 10)
    current = current_start_year
    (current - count + 1..current).to_a.reverse
  end
end
