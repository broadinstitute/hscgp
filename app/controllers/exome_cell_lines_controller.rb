class ExomeCellLinesController < ApplicationController
	before_action :set_exome_cell_line, only: [:show]
	autocomplete :exome_cell_line, :bam_sample_name

	# GET /cell_lines
	# GET /cell_lines.json
	def index
		@cell_lines = ExomeCellLine.all
	end

	# GET /cell_lines/1
	# GET /cell_lines/1.json
	def show
	end

	private
	# Use callbacks to share common setup or constraints between actions.
	def set_exome_cell_line
		@cell_line = ExomeCellLine.find(params[:id])
	end
end
