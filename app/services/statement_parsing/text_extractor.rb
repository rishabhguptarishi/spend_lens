# frozen_string_literal: true

module StatementParsing
  # Layer 1: Extract raw text from PDF/CSV with layout-aware PDF fallback.
  class TextExtractor
    MIN_PDF_TEXT_LENGTH = 100

    def self.extract(file_content, extension:)
      case extension.to_s.downcase
      when 'csv'
        file_content.force_encoding('UTF-8')
      when 'pdf'
        extract_pdf(file_content)
      else
        file_content.to_s
      end
    end

    def self.extract_pdf(content)
      require 'pdf-reader'
      reader = PDF::Reader.new(StringIO.new(content))
      text = reader.pages.map(&:text).join("\n")

      if text.to_s.strip.length < MIN_PDF_TEXT_LENGTH && reader.pages.size.positive?
        layout_text = extract_pdf_via_pdftotext(content)
        text = layout_text if layout_text.to_s.strip.length > text.to_s.strip.length
      end

      text
    rescue => e
      Rails.logger.warn "PDF text extraction failed: #{e.message}"
      extract_pdf_via_pdftotext(content) || ''
    end

    def self.extract_pdf_via_pdftotext(content)
      return '' unless system('which pdftotext > /dev/null 2>&1')

      tmp = Tempfile.create(['stmt', '.pdf'])
      tmp.binmode
      tmp.write(content)
      tmp.flush
      tmp.close
      out = Tempfile.create(['stmt', '.txt'])
      out.close
      system("pdftotext -layout #{tmp.path} #{out.path} 2>/dev/null")
      File.read(out.path).force_encoding('UTF-8')
    rescue => e
      Rails.logger.warn "pdftotext failed: #{e.message}"
      ''
    end
  end
end
