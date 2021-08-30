class ExomeSequenceVariant
	include Mongoid::Document

	# fields
	field :chrom, type: String
	field :pos, type: Integer
	field :ref, type: String
	field :alt, type: String
	field :cell_id, type: String
	field :vqsr, type: String
	field :rs, type: Float
	field :cpg, type: Boolean
	field :an, type: Integer
	field :kg_phase_3, type: Boolean
	field :exac_ac, type: Integer
	field :cosmic_cnt, type: Integer
	field :cosmic_id, type: String
	field :consequence, type: String
	field :impact, type: String
	field :symbol, type: Array
	field :searchable_symbol, type: Array
	field :feature_id, type: Array
	field :hgvs_c, type: String
	field :hgvs_p, type: String
	field :snp_id, type: String
	field :cov, type: Integer
	field :p_val, type: Float
	field :a1_cnt, type: Integer
	field :a2_cnt, type: Integer
	field :af, type: Float
	field :ac, type: Integer

	# indices
	index({ snp_id: 1 }, { unique: false, background: true })
	index({ symbol: 1 }, { unique: false, background: true })
	index({ cell_id: 1 }, { unique: false, background: true })

	# constants used for defining field types when parsing
	FLOAT_FIELDS = %w(rs p_val af)
	BOOLEAN_FIELDS = %w(cpg kg_phase_3)
	INTEGER_FIELDS = %w(pos an exac_ac cosmic_cnt cov a1_cnt a2_cnt ac)
	ARRAY_FIELDS = %w(symbol feature_id)

	# parse source data file into documents, converting values when necessary for floats & booleans
	# uses blocks of 1000 to speed up record creation
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
				exome_sequence_variant = {}
				headers.each_with_index do |header, index|
					unless vals[index].blank? || vals[index].nil?
						if self::FLOAT_FIELDS.include?(header)
							exome_sequence_variant[header] = vals[index].to_f.round(5)
						elsif self::BOOLEAN_FIELDS.include?(header)
							exome_sequence_variant[header] = vals[index].downcase == 'true' ? 1 : 0
						elsif self::INTEGER_FIELDS.include?(header)
							exome_sequence_variant[header] = vals[index].to_i
						elsif self::ARRAY_FIELDS.include?(header)
							exome_sequence_variant[header] = vals[index].split(',').map(&:strip)
						else
							exome_sequence_variant[header] = vals[index]
						end
					end
				end
				exome_sequence_variant[:searchable_symbol] = exome_sequence_variant['symbol'].map(&:downcase)
				@records << exome_sequence_variant
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