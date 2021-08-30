class GenotypeVariant
	include Mongoid::Document

	# fields
	field :phenotype, type: String
	field :variant, type: String
	field :cell_id, type: String
	field :genotype, type: String

	# parse source data file into documents
	def self.parse_source_data(filename, phenotype)
		filepath = Rails.root.join('data', filename)
		if File.exists?(filepath)
			start_time = Time.now
			variant_data = File.open(filepath).readlines
			@counter = 0
			cell_ids = variant_data.shift.split("\t").map(&:strip)
			# remove the first one and last 3 cols as we can compute this on demand
			cell_ids.shift
			cell_ids.pop(3)
			@records = []
			variant_data.each do |line|
				vals = line.split("\t").map(&:strip)
				chrom_pos = vals.shift
				cell_ids.each_with_index do |cell_id, index|
					variant_risk_genotype = {phenotype: phenotype, variant: chrom_pos, cell_id: cell_id, genotype: vals[index]}
					@records << variant_risk_genotype
					@counter += 1
					if @counter % 1000 == 0
						self.create(@records)
						@records = []
						puts "Parsed #{@counter} records..."
					end
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
			puts "Records created: #{@counter}"
			true
		else
			puts "Cannot open file: #{filepath}"
			false
		end
	end

	# get counts for a given genotype and variant
	def self.genotype_count(genotype, variant)
		self.where(genotype: genotype, variant: variant).count
	end

	# get a unique list of phenotypes
	def self.phenotypes
		self.distinct(:phenotype).sort
	end
end