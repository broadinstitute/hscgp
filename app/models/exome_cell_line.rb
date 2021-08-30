class ExomeCellLine
	include Mongoid::Document

	# fields
	field :name, type: String
	field :bam_sample_name, type: String
	field :bam_id, type: Integer

	def self.generate_feature_list(filename)
		filepath = Rails.root.join('data', filename)
		if File.exists?(filepath)
			start_time = Time.now
			cell_line_data = File.open(filepath)
			headers = cell_line_data.readline.split(/[,\t]/).map(&:strip)
			@counter = 0
			while !cell_line_data.eof?
				vals = cell_line_data.readline.split(/[,\t]/).map(&:strip)
				cell_line = {bam_id: @counter + 1}
				headers.each_with_index do |header, index|
					cell_line[header] = vals[index]
				end
				self.create(cell_line)
				@counter += 1
			end
			end_time = Time.now
			time = (end_time - start_time).divmod 60.0
			puts "Finished!"
			puts "Total Time: #{time.first} minutes, #{time.last} seconds"
			puts "Exome Cell Lines created: #{@counter}"
			true
		else
			puts "Cannot open file: #{filepath}"
			false
		end
	end

end