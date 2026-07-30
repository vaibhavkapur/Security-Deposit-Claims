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
      {
        name: model.table_name,
        count: model.count,
        columns: model.column_names - %w[created_at updated_at] - HIDDEN_COLUMNS.fetch(model, []),
        rows: model.order(:id).limit(SAMPLE_ROWS)
      }
    end
  end
end
