class StructuralVariant
	include Mongoid::Document

	field :cnv_id, type: String
	field :chrom, type: String
	field :start, type: Integer
	field :end, type: Integer
	field :cn_category, type: String
	field :cell_id, type: String
	field :genotype, type: Integer
	field :symbol, type: String
	field :searchable_symbol, type: String
	field :gene_overlap, type: String
	field :gene_start, type: Integer
	field :gene_end, type: Integer
	field :cn_dist, type: String
	field :gpc_ctrl_cn_dist, type: String
	field :cnv_type, type: String

	index({ cnv_id: 1 }, { unique: false, background: true })
	index({ symbol: 1 }, { unique: false, background: true })
	index({ cell_id: 1 }, { unique: false, background: true })

	INTEGER_FIELDS = %w(start end gene_start gene_end)

	def self.parse_source_data(filename)
		filepath = Rails.root.join('data', filename)
		if File.exists?(filepath)
			start_time = Time.now
			variant_data = File.open(filepath)
			headers = variant_data.readline.split("\t").map(&:strip)
			cnv_type = 'large'
			# small cnv files have genotype values
			if headers.include?('genotype')
				cnv_type = 'small'
			end
			@counter = 0
			@records = []
			while !variant_data.eof?
				vals = variant_data.readline.split("\t").map(&:strip)
				structural_variant = {}
				headers.each_with_index do |header, index|
					if self::INTEGER_FIELDS.include?(header)
						structural_variant[header] = vals[index].to_i
					else
						structural_variant[header] = vals[index]
					end
				end
				structural_variant[:cnv_type] = cnv_type
				structural_variant[:searchable_symbol] = structural_variant['symbol'].downcase
				@records << structural_variant
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