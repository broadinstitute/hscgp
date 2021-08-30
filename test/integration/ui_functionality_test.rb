require 'test/unit'
require 'selenium-webdriver'

# Unit Test that is actually a user flow test using the Selenium Webdriver to test dev UI directly
class UiFunctionalityTest < Test::Unit::TestCase

	self.test_order = :defined

	def setup
		caps = Selenium::WebDriver::Remote::Capabilities.chrome("chromeOptions" => {'prefs' => {'credentials_enable_service' => false}})
		options = Selenium::WebDriver::Chrome::Options.new
		options.add_argument('--enable-webgl-draft-extensions')
		options.add_argument('--incognito')
		@driver = Selenium::WebDriver::Driver.for :chrome, options: options, desired_capabilities: caps,
																							driver_opts: {log_path: '/tmp/webdriver.log'}
		target_size = Selenium::WebDriver::Dimension.new(1440, 1000)
		@driver.manage.window.size = target_size
		@base_url = 'http://localhost/hscgp'
		@accept_next_alert = true
		@driver.manage.timeouts.implicit_wait = 15
		@test_user = {
				email: 'test.user@gmail.com',
				password: 'password'
		}
		@wait = Selenium::WebDriver::Wait.new(:timeout => 30)
	end

	def teardown
		@driver.quit
	end

	def element_present?(how, what)
		@driver.find_element(how, what)
		true
	rescue Selenium::WebDriver::Error::NoSuchElementError
		false
	end

	def verify(&blk)
		yield
	rescue Test::Unit::AssertionFailedError => ex
		@verification_errors << ex
	end

	def wait_until_page_loads(path)
		@wait.until { @driver.current_url == path }
	end

	# method to close a bootstrap modal by id
	def close_modal(id)
		modal = @driver.find_element(:id, id)
		dismiss = modal.find_element(:class, 'close')
		dismiss.click
		@wait.until {@driver.find_element(:tag_name, 'body')[:class].include?('modal-open') == false}
	end

	# helper method to authenticate for searching
	def sign_in_test_user
		@driver.get(@base_url)
		sign_in_link = @driver.find_element(:id, 'sign-in-nav')
		log_in_click = sign_in_link.click
		email = @driver.find_element(:id, 'user_email')
		email.send_keys(@test_user[:email])
		password = @driver.find_element(:id, 'user_password')
		password.send_keys(@test_user[:password])
		submit = @driver.find_element(:id, 'log-in-btn')
		submit.click
		close_modal('message_modal')
	end

	# wait until element is rendered and visible
	def wait_for_render(how, what)
		@wait.until {@driver.find_element(how, what).displayed? == true}
	end

	test 'get homepage' do
		puts "#{File.basename(__FILE__)}: '#{self.method_name}'"

		@driver.get(@base_url)
		assert element_present?(:class, 'jumbotron'), 'could not find main jumbotron'
		sections = @driver.find_elements(:class, 'index-section')
		assert sections.size == 7, 'found wrong number of site sections, expected 7 but found ' + sections.size.to_s

		puts "#{File.basename(__FILE__)}: '#{self.method_name}' successful!"
	end

	test 'load top-level tabs' do
		puts "#{File.basename(__FILE__)}: '#{self.method_name}'"

		@driver.get(@base_url)
		nav = @driver.find_element(:id, 'site-nav')
		links = nav.find_elements(:tag_name, 'li')
		links.each do |link|
			link.click
			section_id = link.text.split.first.downcase + '-section'
			wait_for_render(:id, section_id)
			assert @driver.find_element(:id, section_id).displayed?, "#{link.text} section not displayed"
		end

		puts "#{File.basename(__FILE__)}: '#{self.method_name}' successful!"
	end

	# perform basic search for TP53
	test 'whole genome search' do
		puts "#{File.basename(__FILE__)}: '#{self.method_name}'"

		# sign in first
		sign_in_test_user

		# perform search
		search_nav = @driver.find_element(:id, 'wgs-nav')
		search_nav.click
		wait_for_render(:id, 'basic-search')
		@driver.find_element(:id, 'whole_genome_search_genes').send_key('TP53')
		@driver.find_element(:id, 'search-wgs-btn').click
		assert element_present?(:id, 'search-results-table'), 'could not find results table'
		assert element_present?(:id, 'results_info'), 'could not find results info'
		results_text = @driver.find_element(:id, 'results_info').text
		result_count = results_text.split[5].to_i
		assert result_count > 0, 'Did not find any results, exected at least one but found ' + result_count.to_s
		@driver.find_element(:id, 'summary-tab-nav').click
		assert @driver.find_elements(:class, 'js-plotly-plot').size == 4, 'could not find all summary plots'
		@driver.find_element(:id, 'igv-tab-nav').click
		wait_for_render(:id, 'igvRootDiv')
		igv_tracks = @driver.find_elements(:class, 'igv-track-div')
		assert igv_tracks.size == 6, 'Did not find correct number of IGV tracks, expected 6 but found ' + igv_tracks.size.to_s

		puts "#{File.basename(__FILE__)}: '#{self.method_name}' successful!"
	end

	# perform exome search for TP53
	test 'exome search' do
		puts "#{File.basename(__FILE__)}: '#{self.method_name}'"

		# sign in first
		sign_in_test_user

		# perform search
		search_nav = @driver.find_element(:id, 'exome-nav')
		search_nav.click
		wait_for_render(:id, 'exome-section')
		@driver.find_element(:id, 'exome_search_genes').send_key('TP53')
		@driver.find_element(:id, 'search-exome-btn').click
		assert element_present?(:id, 'exome-search-results-table'), 'could not find results table'
		assert element_present?(:id, 'exome-results_info'), 'could not find results info'
		results_text = @driver.find_element(:id, 'exome-results_info').text
		result_count = results_text.split[5].to_i
		assert result_count > 0, 'Did not find any results, exected at least one but found ' + result_count.to_s
		@driver.find_element(:id, 'igv-exome-tab-nav').click
		wait_for_render(:id, 'igvRootDiv')
		igv_tracks = @driver.find_elements(:class, 'igv-track-div')
		assert igv_tracks.size == 5, 'Did not find correct number of IGV tracks, expected 5 but found ' + igv_tracks.size.to_s

		puts "#{File.basename(__FILE__)}: '#{self.method_name}' successful!"
	end

	# perform genotype search for all genotypes in Mshef10_P22
	test 'genotype search' do
		puts "#{File.basename(__FILE__)}: '#{self.method_name}'"

		# sign in first
		sign_in_test_user

		# perform search
		search_nav = @driver.find_element(:id, 'wgs-nav')
		search_nav.click
		wait_for_render(:id, 'basic-search')
		genotype_nav = @driver.find_element(:id, 'genotype-search-nav')
		genotype_nav.click
		wait_for_render(:id, 'genotype-search')
		@driver.find_element(:id, 'genotype_search_cell_lines').send_key('Mshef10_P22')
		@driver.find_element(:id, 'genotype_search_genotypes').find_elements(tag_name: 'option').each(&:click)
		@driver.find_element(:id, 'genotype-search-btn').click
		wait_for_render(:id, 'search-results-table')
		assert element_present?(:id, 'search-results-table'), 'could not find results table'
		assert element_present?(:id, 'results_info'), 'could not find results info'
		@driver.find_element(:id, 'gen-summary-tab-nav').click
		assert @driver.find_elements(:class, 'js-plotly-plot').size == 1, 'could not find summary plot'
		@driver.find_element(:id, 'circos-tab-nav').click
		assert @driver.find_elements(:id, 'biocircos'), 'could not find biocircos plot'

		puts "#{File.basename(__FILE__)}: '#{self.method_name}' successful!"
	end

	# load precomputed heatmap
	test 'precomputed heatmap search' do
		puts "#{File.basename(__FILE__)}: '#{self.method_name}'"

		# sign in first
		sign_in_test_user

		# perform search
		search_nav = @driver.find_element(:id, 'wgs-nav')
		search_nav.click
		wait_for_render(:id, 'basic-search')
		precomputed_nav = @driver.find_element(:id, 'precomputed-analysis-nav')
		precomputed_nav.click
		wait_for_render(:id, 'precomputed-analyses')

		precomputed_view = @driver.find_element(:id, 'view-precomputed')
		precomputed_view.click
		wait_for_render(:id, 'heatmap-target')
		assert @driver.find_elements(:id, 'heatmap-target'), 'could not find heatmap plot'

		puts "#{File.basename(__FILE__)}: '#{self.method_name}' successful!"
	end

	# load circos data for small & large CNVs
	test 'circos data plot' do
		puts "#{File.basename(__FILE__)}: '#{self.method_name}'"

		# sign in first
		sign_in_test_user

		# perform search
		search_nav = @driver.find_element(:id, 'wgs-nav')
		search_nav.click
		wait_for_render(:id, 'basic-search')
		circos_nav = @driver.find_element(:id, 'circos-tab-nav')
		circos_nav.click
		wait_for_render(:id, 'circos-results-tabs')
		assert @driver.find_elements(:class, 'circos-tab-nav').size == 4, 'did not find correct number of circos tabs'
		# load each plot
		# large deletions
		large_deletions = @driver.find_element(:id, 'lg-deletions-tab-nav')
		large_deletions.click
		wait_for_render(:id, 'lg-deletions-biocircos')
		large_deletions_plot = @driver.find_element(:id, 'lg-deletions-biocircos')
		assert large_deletions_plot.find_element(:tag_name, 'svg').displayed?, 'could not find large deletion circos plot'

		# large duplications
		large_duplications = @driver.find_element(:id, 'lg-duplications-tab-nav')
		large_duplications.click
		wait_for_render(:id, 'lg-duplications-biocircos')
		large_duplications_plot = @driver.find_element(:id, 'lg-duplications-biocircos')
		assert large_duplications_plot.find_element(:tag_name, 'svg').displayed?, 'could not find large duplication circos plot'

		# large cnn-loh
		large_loh = @driver.find_element(:id, 'lg-loh-tab-nav')
		large_loh.click
		wait_for_render(:id, 'lg-loh-biocircos')
		large_loh_plot = @driver.find_element(:id, 'lg-loh-biocircos')
		assert large_loh_plot.find_element(:tag_name, 'svg').displayed?, 'could not find large cnn circos plot'

		# small regions
		small_deletions = @driver.find_element(:id, 'sm-regions-tab-nav')
		small_deletions.click
		wait_for_render(:id, 'sm-regions')

		# select a plot
		chromosome = @driver.find_element(:id, 'small_circos_region_chrom')
		chromosome.send_keys('15')
		category = @driver.find_element(:id, 'small_circos_region_category')
		category.send_keys('Deletion')
		submit = @driver.find_element(:id, 'load-sm-region')
		submit.click

		wait_for_render(:id, 'sm-biocircos-target')
		small_deletions_plot = @driver.find_element(:id, 'sm-biocircos-target')
		assert small_deletions_plot.find_element(:tag_name, 'svg').displayed?, 'could not find small region circos plot'

		puts "#{File.basename(__FILE__)}: '#{self.method_name}' successful!"
	end

end