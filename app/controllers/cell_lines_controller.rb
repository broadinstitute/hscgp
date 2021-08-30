class CellLinesController < ApplicationController
  before_action :set_cell_line, only: [:show]
  autocomplete :cell_line, :sample_name

  # GET /cell_lines
  # GET /cell_lines.json
  def index
    @cell_lines = CellLine.all.keep_if {|x| not x["hide"]}
  end

  # GET /cell_lines/1
  # GET /cell_lines/1.json
  def show
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_cell_line
      @cell_line = CellLine.find(params[:id]).keep_if {|x| not x["hide"]}
    end
end
