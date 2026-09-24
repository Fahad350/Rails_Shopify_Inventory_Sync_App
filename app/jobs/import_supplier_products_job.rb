class ImportSupplierProductsJob
  include Sidekiq::Job

  def perform
    SupplierCsvImporter.call
  end
end