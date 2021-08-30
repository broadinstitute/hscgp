class LargeCircosStructuralVariant
	include Mongoid::Document

	field :chrom, type: String
	field :start, type: Integer
	field :end, type: Integer
	field :cell_id, type: String
	field :length, type: Float
	field :gse_length, type: Float
	field :copy_number, type: Float
	field :p_value, type: Float
	field :variant_type, type: String
	field :category, type: String

	index({ category: 1 }, { unique: false, background: true })

	# constants used for defining field types when parsing
	FLOAT_FIELDS = %w(length gse_length copy_number p_value)
	INTEGER_FIELDS = %w(start end)

	# generic parser to create records
	def self.parse_source_data(filename)
		filepath = Rails.root.join('data', filename)
		if File.exists?(filepath)
			start_time = Time.now
			variant_data = File.open(filepath)
			headers = variant_data.readline.split("\t").map(&:strip)
			@counter = 0
			@records = []
			while !variant_data.eof?
				vals = variant_data.readline.split("\t").map(&:strip)
				lg_strct_variant = {}
				headers.each_with_index do |header, index|
					unless vals[index].blank? || vals[index].nil?
						if self::FLOAT_FIELDS.include?(header)
							lg_strct_variant[header] = vals[index].to_f.round(5)
						elsif self::INTEGER_FIELDS.include?(header)
							lg_strct_variant[header] = vals[index].to_i
						else
							lg_strct_variant[header] = vals[index]
						end
					end
				end
				@records << lg_strct_variant
				@counter += 1
				if @counter % 1000 == 0
					self.create(@records)
					@records = []
					puts "Parsed #{@counter} records..."
				end
			end
			unless @records.empty?
				self.create(@records)
				puts "Parsed #{@counter} records..."
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
end