# frozen_string_literal: true

module Investments
  # Source priority ranks (per docs/INVESTMENT_ARCHITECTURE.html §5.4).
  # Higher = more authoritative. ActivityReconcilerService uses these to
  # decide which competing view of "same event" is canonical when two
  # different ingestion paths attest to the same instrument + date +
  # amount.
  #
  #   100 — cdsl_cas / nsdl_cas (depository's own record; gold standard)
  #    95 — mf_cas (CAMS / KFin / MFU; registrar's own record)
  #    90 — tax_doc (broker P&L / MF CG document; audit-grade)
  #    80 — broker_import (broker-issued CSV/PDF; user could have edited)
  #    75 — bank_statement (passbook FD/RD/PPF block; bank's own record)
  #    60 — bank_detect (suggestion accepted from a UPI/NEFT narration)
  #    40 — manual (user-typed)
  module SourcePriority
    extend self

    PRIORITIES = {
      'cdsl_cas'        => 100,
      'nsdl_cas'        => 100,
      'epf_passbook'    => 95,
      'nps_statement'   => 95,
      'amc_direct'      => 95,
      'mf_cas'          => 95,
      'cams_cas'        => 95,
      'kfintech_cas'    => 95,
      'tax_doc'         => 90,
      'broker_pl'       => 90,
      'mf_cg'           => 90,
      'broker_import'   => 80,
      'bank_statement'  => 75,
      'bank_detect'     => 60,
      'manual'          => 40,
    }.freeze

    DEFAULT = 50

    def for(source)
      PRIORITIES.fetch(source.to_s, DEFAULT)
    end
  end
end
