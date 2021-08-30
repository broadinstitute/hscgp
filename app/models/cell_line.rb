class CellLine
	include Mongoid::Document

	# fields
	field :name, type: String
	field :institution, type: String
	field :sample_name, type: String
	field :bam_sample_name, type: String
	field :gender, type: String
	field :sexgenotype, type: String
	field :mean_seq_coverage, type: Float
	field :median_seq_coverage, type: Integer
	field :banked, type: String
	field :culture_system, type: String
	field :passaging, type: String
	field :substrate, type: String
	field :media, type: String
	field :seq_platform, type: String
	field :read_length, type: String
	field :samples_submitted, type: Integer
	field :nih_registration_number, type: String
	field :ref_genome, type: String
	field :alignment_program_used, type: String
        field :hide, type: Boolean
	field :bam_id, type: Integer
        field :bam_path, type: String
        field :bai_path, type: String
        field :bucket, type: String
        field :workspace, type: String

	# indices
	index({ name: 1 }, { unique: true })
	index({ sample_name: 1 }, { unique: true })
	index({ bam_sample_name: 1 }, { unique: true })

	# field definitions
	INTEGER_FIELDS = %w(median_seq_coverage samples_submitted)
	FLOAT_FIELDS = %w(mean_seq_coverage)

	def self.generate_feature_list(filename)
		filepath = Rails.root.join('data', filename)
		if File.exists?(filepath)
			start_time = Time.now
			cell_line_data = File.open(filepath)
			headers = cell_line_data.readline.split("\t").map(&:strip)
			@counter = 0
			while !cell_line_data.eof?
				vals = cell_line_data.readline.split("\t").map(&:strip)
				cell_line = {bam_id: @counter + 1}
				headers.each_with_index do |header, index|
					if self::INTEGER_FIELDS.include?(header)
						cell_line[header] = vals[index].to_i
					elsif self::FLOAT_FIELDS.include?(header)
						cell_line[header] = vals[index].to_f
					else
						cell_line[header] = vals[index]
					end
				end
				self.create(cell_line)
				@counter += 1
			end
			end_time = Time.now
			time = (end_time - start_time).divmod 60.0
			puts "Finished!"
			puts "Total Time: #{time.first} minutes, #{time.last} seconds"
			puts "Cell Lines created: #{@counter}"
			true
		else
			puts "Cannot open file: #{filepath}"
			false
		end
	end

	# parse new bam locations file
	# must at least contain bam_id, name, sample_name, 'project' (whether or not bam is new addition)
	def self.update_bam_samples_and_ids(filename)
		filepath = Rails.root.join('data', filename)
		if File.exists?(filepath)
			start_time = Time.now
			cell_line_data = File.open(filepath)
			headers = cell_line_data.readline.split("\t").map(&:strip)
			bam_index = headers.index('bam_id')
			project_index = headers.index('project')
			name_index = headers.index('name')
			sample_index = headers.index('sample_name')
			while !cell_line_data.eof?
				vals = cell_line_data.readline.split("\t").map(&:strip)
				bam_id = vals[bam_index]
				new_file = vals[project_index] == 'new'
				unless new_file
					cell_line = CellLine.find_by(bam_id: bam_id)
					if vals[name_index] != cell_line.name && vals[sample_index] != cell_line.bam_sample_name
						puts "Updating #{cell_line.name}, #{cell_line.bam_sample_name} (#{cell_line.bam_id}) to #{vals[name_index]}, #{vals[sample_index]}"
						cell_line.update(name: vals[name_index], bam_sample_name: vals[sample_index])
					else
						puts "No update needed for #{cell_line.name}, #{cell_line.bam_sample_name} (#{cell_line.bam_id})"
					end
				else
					puts "Adding new entry: #{vals[name_index]}, #{vals[sample_index]} (#{bam_id})"
					CellLine.create(bam_id: bam_id, name: vals[name_index], sample_name: vals[sample_index], bam_sample_name: vals[sample_index])
				end
			end
			end_time = Time.now
			time = (end_time - start_time).divmod 60.0
			puts "Finished!"
			puts "Total Time: #{time.first} minutes, #{time.last} seconds"
			true
		else
			puts "Cannot open file: #{filepath}"
			false
		end
	end

	def seq_results_count
		SequenceVariant.where(cell_id: self.sample_name).count
	end

	def cnv_results_count
		StructuralVariant.where(cell_id: self.sample_name).count
	end

	def results_count
		self.seq_results_count + self.cnv_results_count
	end

end
