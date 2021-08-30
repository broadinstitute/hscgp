class SequenceVariant
	include Mongoid::Document

	# fields
	field :snp_id, type: String
        field :rsid, type: String
	field :chrom, type: String
	field :pos, type: Integer
	field :ref, type: String
	field :alt, type: String
	field :consequence, type: String
	field :symbol, type: Array
	field :searchable_symbol, type: Array
	field :cell_id, type: String
	field :genotype, type: String
	field :ac, type: Integer
	field :an, type: Integer
	field :hesc_af, type: Float
	field :clinvar_hit, type: Boolean
	field :sift, type: String
	field :polyphen, type: String
	field :singleton, type: Boolean
	field :indel, type: Boolean
	field :in_exac, type: Boolean
	field :ac_adj, type: Integer
	field :an_adj, type: Integer
	field :exac_af_adj, type: Float
        field :gnomad_af, type: Float
        field :cadd, type: Float
        field :dann, type: Float

	# indices
	index({ snp_id: 1 }, { unique: false, background: true })
	index({ symbol: 1 }, { unique: false, background: true })
	index({ cell_id: 1 }, { unique: false, background: true })

	# constants used for defining field types when parsing
	FLOAT_FIELDS = %w(hesc_af exac_af_adj cadd dann gnomad_af)
	BOOLEAN_FIELDS = %w(clinvar_hit singleton indel in_exac)
	INTEGER_FIELDS = %w(pos ac an ac_adj an_adj)
	ARRAY_FIELDS = %w(symbol)

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
				sequence_variant = {}
				headers.each_with_index do |header, index|
					unless vals[index].blank? || vals[index].nil?
						if self::FLOAT_FIELDS.include?(header)
							sequence_variant[header] = vals[index].to_f.round(5)
						elsif self::BOOLEAN_FIELDS.include?(header)
							sequence_variant[header] = vals[index].downcase == 'true' ? 1 : 0
						elsif self::INTEGER_FIELDS.include?(header)
							sequence_variant[header] = vals[index].to_i
						elsif self::ARRAY_FIELDS.include?(header)
							sequence_variant[header] = vals[index].split(',').map(&:strip)
						else
							sequence_variant[header] = vals[index]
						end
					end
				end
				sequence_variant[:searchable_symbol] = sequence_variant['symbol'].map(&:downcase)
				@records << sequence_variant
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

	# compress name of introns/exons to render better in IGV
	def self.edit_bed_file(filename)
		filepath = Rails.root.join('public', filename)
		count = 0
		start_time = Time.now
		if File.exists?(filepath)
			name = filename.split('.').first
			outfile = File.new(name + '_edited.bed', 'w')
			bed_data = File.open(filepath)
			while !bed_data.eof?
				row = bed_data.readline.split("\t").map(&:strip)
				existing_feature = row[3]
				gene = existing_feature.split('.').first
				# grab exon/intron name and number from existing entry and reformat
				feature = existing_feature.split('_')[1..3].join('_')
				new_name = "#{gene}_#{feature}"
				# reconcatenate row and write
				newline = [row[0], row[1], row[2], new_name, row[4], row[5]].join("\t")
				outfile.write newline + "\n"
				count += 1
			end
			outfile.close
			end_time = Time.now
			time = (end_time - start_time).divmod 60.0
			puts "Finished!"
			puts "Rows processed: #{count}"
			puts "Total Time: #{time.first} minutes, #{time.last} seconds"
		end
	end
end
