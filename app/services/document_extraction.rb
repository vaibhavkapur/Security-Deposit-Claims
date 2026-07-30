require "anthropic"
require "base64"

# Extracts structured line items from a claim document via the Claude API.
#
# Extractable doc types (ledgers, move-out statements, SDI forms, itemizations,
# invoices, deposit dispositions) are sent to Claude as PDFs/images; the model
# returns the itemized charges through a forced tool call, which lands in
# documents.extracted_json and is promoted into claim_line_items rows.
# Charges are positive amounts, credits/payments negative. Dispositions are
# left "pending" for the adjudication engine (Stage 2) to classify.
class DocumentExtraction
  EXTRACTOR_VERSION = "v1/claude-opus-5".freeze
  MODEL = :"claude-opus-5"

  EXTRACTABLE_DOC_TYPES = %w[
    ledger move_out_statement sdi_form itemization invoice deposit_disposition
  ].freeze
  MAX_FILE_BYTES = 20 * 1024 * 1024 # keep under the 32MB request limit

  CATEGORIES = %w[
    unpaid_rent late_fee damage cleaning painting carpet_replacement rekey
    trash_removal utility insurance_fee admin_fee reletting_fee notice_fee
    lease_break_fee legal_fee pet_fee credit payment other
  ].freeze

  EXTRACTION_TOOL = {
    name: "record_extraction",
    description: "Record the structured data extracted from a security deposit claim document.",
    input_schema: {
      type: "object",
      additionalProperties: false,
      required: ["line_items"],
      properties: {
        document_date: {type: %w[string null], description: "Date on the document, YYYY-MM-DD, or null"},
        tenant_name: {type: %w[string null], description: "Tenant name(s) on the document, or null"},
        property_address: {type: %w[string null], description: "Property address on the document, or null"},
        total_amount: {type: %w[number null], description: "The document's stated total/balance due, or null"},
        line_items: {
          type: "array",
          description: "Every itemized charge, credit, or payment on the document",
          items: {
            type: "object",
            additionalProperties: false,
            required: %w[description category amount],
            properties: {
              date: {type: %w[string null], description: "Transaction date, YYYY-MM-DD, or null"},
              description: {type: "string", description: "The charge description as written"},
              category: {type: "string", enum: CATEGORIES},
              amount: {type: "number", description: "Positive for charges, negative for credits/payments"}
            }
          }
        },
        notes: {type: %w[string null], description: "Anything ambiguous or unusual worth flagging, or null"}
      }
    }
  }.freeze

  PROMPT = <<~PROMPT.freeze
    This document is part of a residential security deposit insurance claim
    (a property manager's evidence of tenant charges). Extract every itemized
    charge, credit, and payment it contains and record the result with the
    record_extraction tool. Transcribe amounts exactly as written; classify
    each row's category conservatively (use "other" when unsure) and note
    anything ambiguous in "notes". If the document contains no itemized
    amounts, record an empty line_items array.
  PROMPT

  def initialize(document)
    @document = document
  end

  def call
    unless EXTRACTABLE_DOC_TYPES.include?(@document.doc_type)
      return mark("not_extractable", error: "doc_type #{@document.doc_type} is not extracted")
    end

    source = content_block
    return unless source # mark() already called

    response = client.messages.create(
      model: MODEL,
      max_tokens: 16_000,
      tools: [EXTRACTION_TOOL],
      tool_choice: {type: "tool", name: "record_extraction"},
      messages: [{role: "user", content: [source, {type: "text", text: PROMPT}]}]
    )

    if response.stop_reason == :refusal
      return mark("refused", error: "model declined the request")
    end

    tool_use = response.content.find { |block| block.type == :tool_use }
    if tool_use.nil?
      return mark("failed", error: "no tool_use block in response (stop_reason: #{response.stop_reason})")
    end

    extracted = tool_use.input.to_h.deep_stringify_keys
    ActiveRecord::Base.transaction do
      ClaimLineItem.where(document_id: @document.id).delete_all
      Array(extracted["line_items"]).each do |item|
        ClaimLineItem.create!(
          claim_id: @document.claim_id,
          document_id: @document.id,
          txn_date: parse_date(item["date"]),
          description: item["description"].presence || "(blank)",
          category: item["category"].presence || "other",
          amount: item["amount"]
        )
      end
      @document.update!(
        extraction_status: "extracted",
        extracted_json: extracted,
        extracted_at: Time.current,
        extractor_version: EXTRACTOR_VERSION,
        extraction_error: nil
      )
    end
    @document
  rescue Anthropic::Errors::APIStatusError => e
    mark("failed", error: "#{e.class.name.demodulize}: #{e.message.to_s.truncate(200)}")
  end

  private

  def client
    @client ||= Anthropic::Client.new
  end

  def content_block
    path = @document.storage_path
    return mark("failed", error: "file missing from storage") && nil unless File.exist?(path)
    if File.size(path) > MAX_FILE_BYTES
      return mark("not_extractable", error: "file exceeds #{MAX_FILE_BYTES / 1_048_576}MB") && nil
    end

    data = Base64.strict_encode64(File.binread(path))
    case @document.mime_type
    when "application/pdf"
      {type: "document", source: {type: "base64", media_type: "application/pdf", data: data}}
    when "image/jpeg", "image/png", "image/gif", "image/webp"
      {type: "image", source: {type: "base64", media_type: @document.mime_type, data: data}}
    else
      mark("not_extractable", error: "unsupported mime type #{@document.mime_type}") && nil
    end
  end

  def mark(status, error: nil)
    @document.update!(
      extraction_status: status,
      extraction_error: error,
      extractor_version: EXTRACTOR_VERSION
    )
    @document
  end

  def parse_date(value)
    Date.parse(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end
end
