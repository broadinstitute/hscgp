class PrecomputedHeatmap
	include Mongoid::Document

	# class to store data in form ready to plot as heatmap in Plotly
	# fields

	field :title, type: String
	field :description, type: String
	field :samples, type: Array
	field :features, type: Array
	field :scores, type: Array

	# parse source data from file into collection
	def self.parse_source_data(filename, title, description)
		filepath = Rails.root.join('data', filename)
		if File.exists?(filepath)
			start_time = Time.now
			heatmap_data = File.open(filepath)
			headers = heatmap_data.readline.chomp.split("\t").map(&:strip)
			headers.shift
			features = headers
			samples = []
			scores = []
			while !heatmap_data.eof?
				vals = heatmap_data.readline.chomp.split("\t").map(&:strip)
				samples << vals.shift
				scores << vals
			end
			self.create({title: title, description: description, samples: samples, features: features, scores: scores})
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

	# create nested array for using in select input
	def self.create_select_options
		self.all.map {|ph| [ph.title, ph._id]}
	end
end