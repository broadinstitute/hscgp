class Gene
	include Mongoid::Document

	# fields
	field :symbol, type: String

	# indices
	index({ symbol: 1 }, { unique: true })

	def self.generate_feature_list
		# flatten symbol list from SequenceVariants as they can be arrays
		symbols = (SequenceVariant.pluck(:symbol).flatten + StructuralVariant.pluck(:symbol)).uniq
		self.create(symbols.map {|s| {symbol: s}})
		puts "Finished!"
		puts "Genes created: #{symbols.size}"
		true
	end
end