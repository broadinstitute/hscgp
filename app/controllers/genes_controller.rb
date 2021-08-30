class GenesController < ApplicationController
  before_action :set_gene, only: [:show]
  autocomplete :gene, :symbol

  # GET /genes
  # GET /genes.json
  def index
    @seq_gene_distribution = Gene.all
  end

  # GET /genes/1
  # GET /genes/1.json
  def show
  end

  private
  # Use callbacks to share common setup or constraints between actions.
  def set_gene
    @gene = Gene.find(params[:id])
  end
end
