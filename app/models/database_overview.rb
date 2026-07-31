# Snapshot of every imported table for display on the import page.
class DatabaseOverview
  SPREADSHEET_MODELS = [PmCompany, PropertyManager, Property, Policy,
                        Lease, Tenant, Claim, CollectionRecord,
                        ClaimActivity].freeze
  PDF_MODELS = [Document, ClaimLineItem].freeze
  ADJUDICATION_MODELS = [AdjudicationDecision].freeze
  MODELS = (SPREADSHEET_MODELS + PDF_MODELS + ADJUDICATION_MODELS).freeze
  SAMPLE_ROWS = 5
  HIDDEN_COLUMNS = {}.freeze

  # Wipe all imported data and reset ID sequences; table structure stays.
  def self.clear!
    table_names = MODELS.map(&:table_name).join(", ")
    ActiveRecord::Base.connection.execute(
      "TRUNCATE #{table_names} RESTART IDENTITY CASCADE"
    )
    FileUtils.rm_rf(Document::STORAGE_ROOT)
  end

  def self.spreadsheet_tables
    tables(SPREADSHEET_MODELS)
  end

  def self.pdf_tables
    tables(PDF_MODELS)
  end

  def self.adjudication_tables
    tables(ADJUDICATION_MODELS)
  end

  def self.tables(models = MODELS)
    models.map do |model|
      scope = display_scope(model)
      {
        name: model.table_name,
        count: scope.count,
        total: model.count,
        columns: model.column_names - %w[created_at updated_at] - HIDDEN_COLUMNS.fetch(model, []),
        rows: sample_rows(model, scope)
      }
    end
  end

  # Before extraction runs, show every imported document; once any document
  # has extracted content, show only those (the extraction is the point).
  def self.display_scope(model)
    return model.all unless model == Document

    extracted = Document.where.not(extracted_json: nil)
    extracted.exists? ? extracted : Document.all
  end

  # First-N-by-id makes adjudication_decisions look monotonous (long runs of
  # identical declines), so sample it for variety: dedupe by outcome + reason
  # shape, then alternate outcomes.
  def self.sample_rows(model, scope)
    return scope.order(:id).limit(SAMPLE_ROWS) unless model == AdjudicationDecision

    AdjudicationDecision.find_by_sql(<<~SQL)
      WITH distinct_reasons AS (
        SELECT DISTINCT ON (outcome, left(reason, 40)) *
        FROM adjudication_decisions
        ORDER BY outcome, left(reason, 40), id
      )
      SELECT * FROM (
        SELECT *, row_number() OVER (PARTITION BY outcome ORDER BY id) AS rn
        FROM distinct_reasons
      ) ranked
      ORDER BY rn, outcome
      LIMIT #{SAMPLE_ROWS}
    SQL
  end
end
