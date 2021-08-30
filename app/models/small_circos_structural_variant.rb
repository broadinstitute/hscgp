class SmallCircosStructuralVariant
	include Mongoid::Document

	field :cnv_id, type: String
	field :chrom, type: String
	field :start, type: Integer
	field :end, type: Integer
	field :gscn_min, type: Integer
	field :gsn_non_ref, type: Integer
	field :gscn_category, type: String

	index({ cnv_id: 1 }, { unique: false, background: true })
	index({ gscn_category: 1 }, { unique: false, background: true })

	# constants used for defining field types when parsing
	INTEGER_FIELDS = %w(start end gscn_min gsn_non_ref)

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
				sm_strct_variant = {}
				headers.each_with_index do |header, index|
					unless vals[index].blank? || vals[index].nil?
						if self::INTEGER_FIELDS.include?(header)
							sm_strct_variant[header] = vals[index].to_i
						else
							sm_strct_variant[header] = vals[index]
						end
					end
				end
				@records << sm_strct_variant
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
