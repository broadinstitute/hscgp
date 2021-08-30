class SiteController < ApplicationController

  respond_to :html, :js

  # for changing colorscales on certain Plotly plots
  COLORSCALE_THEMES = %w(Blackbody Bluered Blues Earth Electric Greens Hot Jet Picnic Portland Rainbow RdBu Reds Viridis YlGnBu YlOrRd)
  # default chromosome colors for BioCircos
  BIOCIRCOS_COLORS = {
      '1' => 'rgb(151,79,0)',
      '2' => 'rgb(83,85,0)',
      '3' => 'rgb(134,139,11)',
      '4' => 'rgb(231,0,0)',
      '5' => 'rgb(255,0,0)',
      '6' => 'rgb(255,0,294)',
      '7' => 'rgb(255,186,192)',
      '8' => 'rgb(255,123,0)',
      '9' => 'rgb(255,191,0)',
      '10' => 'rgb(254,255,0)',
      '11' => 'rgb(161,255,0)',
      '12' => 'rgb(0,255,0)',
      '13' => 'rgb(0,116,0)',
      '14' => 'rgb(15,0,196)',
      '15' => 'rgb(57,131,255)',
      '16' => 'rgb(107,194,255)',
      '17' => 'rgb(0,255,255)',
      '18' => 'rgb(163,255,255)',
      '19' => 'rgb(163,0,195)',
      '20' => 'rgb(231,0,255)',
      '21' => 'rgb(213,120,255)',
      '22' => 'rgb(83,83,83)',
      'X' => 'rgb(135,135,135)',
      'Y' => 'rgb(193,193,193)'
  }

  CHROMOSOMES = %w(1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 X Y)

  before_action :authenticate_user!, except: :index
  before_action :authenticate_admin, only: [:user_whitelist, :add_user_to_whitelist, :remove_user_from_whitelist]
  before_action :cors_set_access_control_headers, only: [:whole_genome_search, :exome_search]

  def index
    @help_request = HelpRequest.new
    @contact_error = false
    @cells = CellLine.all.sort_by(&:name)
  end

  def help_request
    @help_request = HelpRequest.new(help_request_params)
    unless verify_recaptcha?(params[:recaptcha_token], 'help_request')
      flash.now[:error] = t('recaptcha.errors.verification_failed')
      @contact_error = true
      @cells = CellLine.all.sort_by(&:name) # .keep_if {|cell| cell.results_count > 0 and not cell["hide"]}
      return render :index
    end
    HescMailer.help_request(@help_request).deliver_now
    redirect_to site_path, notice: 'Your message has been delivered. You can expect a followup email addressing your question within 48 hours.'
  end

  def whole_genome_search
    # make sure user hasn't requested too many cell lines
    if params[:whole_genome_search][:cell_lines].any?
      cells = params[:whole_genome_search][:cell_lines].first.split
      if cells.size > 4
        render :too_many_cell_lines and return
      end
    end

    client = FireCloudClient.new('broad-genomics-delivery', 'credentials.json')

    # search for variants
    @query = sanitize_search(:whole_genome_search)
    @cnv_query = sanitize_structural_variant_search
    @results = SequenceVariant.where(@query).to_a.keep_if {|x| not x["hide"]}
    if params[:whole_genome_search][:variants].blank?
      @all_cnv_results = StructuralVariant.where(@cnv_query).to_a
    else
      variants = parse_search_terms(:whole_genome_search, :variants)
      variant_query = []
      variants.each do |variant|
        chrom, pos, ref, snp = variant.split(':')
        variant_query << {chrom: chrom, :start.lte => pos.to_i, :end.gte => pos.to_i}
      end
      @all_cnv_results = StructuralVariant.or(variant_query).where(@cnv_query).to_a
    end
    # split cnvs by type
    @small_cnv = []
    @large_cnv = []
    @all_cnv_results.each do |cnv|
      cnv.cnv_type == 'small' ? @small_cnv << cnv : @large_cnv << cnv
    end

    # assemble data objects for summary histograms
    het = 0
    hom = 0
    in_exac = 0
    not_in_exac = 0
    clinvar_hit = 0
    not_clinvar_hit = 0
    indel = 0
    not_indel = 0
    singleton = 0
    not_singleton = 0
    variant_consequence = {}
    cell_ids = {}
    # parse results once, grabbing necesssary counts and data
    @results.each do |result|
      result.genotype == 'HET' ? het += 1 : hom += 1
      result.clinvar_hit == 'HET' ? clinvar_hit += 1 : not_clinvar_hit += 1
      result.singleton == 'HET' ? singleton += 1 : not_singleton += 1
      result.indel == 'HET' ? indel += 1 : not_indel += 1
      result.genotype == 'HET' ? in_exac += 1 : not_in_exac += 1
      if variant_consequence[result.consequence].nil?
        variant_consequence[result.consequence] = 1
      else
        variant_consequence[result.consequence] += 1
      end
      if cell_ids[result.cell_id].nil?
        cell_ids[result.cell_id] = 1
      else
        cell_ids[result.cell_id] += 1
      end
    end

    # group results by symbol, sort and take top 100
    sorted_genes = @results.group_by(&:symbol).map {|sym, res| [sym.first, res.size]}.sort_by {|sym, size| -size}.take(100)
    cnv_sorted_genes = @all_cnv_results.group_by(&:symbol).map {|sym, res| [sym, res.size]}.sort_by {|sym, size| -size}.take(100)

    # format data for Plotly
    @boolean_data = [
        {x: ['Heterozygous', 'Homozygous'], y: [het, hom], type: 'bar', name: 'Genotypes'},
        {x: ['In ExAC', 'Not in ExAC'], y: [in_exac, not_in_exac], type: 'bar', name: 'ExAC Status'},
        {x: ['ClinVar hit', 'Not ClinVar hit'], y: [clinvar_hit, not_clinvar_hit], type: 'bar', name: 'ClinVar Status'},
        {x: ['Indel', 'Not indel'], y: [indel, not_indel], type: 'bar', name: 'Indels'},
        {x: ['Singleton', 'Not singleton'], y: [singleton, not_singleton], type: 'bar', name: 'Singletons'}
    ]

    @consequence_data = []
    variant_consequence.each do |cons, count|
      @consequence_data << {x: [cons], y: [count], type: 'bar', name: "#{cons.split('_').map(&:capitalize).join(" ")}"}
    end

    @seq_gene_distribution = [{x: sorted_genes.map(&:first), y: sorted_genes.map(&:last), type: 'bar', name: 'Genes'}]
    @cnv_gene_distribution = [{x: cnv_sorted_genes.map(&:first), y: cnv_sorted_genes.map(&:last), type: 'bar', name: 'Genes'}]

    # collect IGV tracks
    @tracks = [
        {
            url: '//s3.amazonaws.com/igv.broadinstitute.org/annotations/hg19/genes/gencode.v18.annotation.sorted.gtf.gz',
            indexURL: '//s3.amazonaws.com/igv.broadinstitute.org/annotations/hg19/genes/gencode.v18.annotation.sorted.gtf.gz.tbi',
            name: 'Gencode v18 Annotations GTF',
            format: 'gtf',
            displayMode: 'SQUISHED',
            visibilityWindow: 10000000
        }
    ]

    # fetch token, check if still valid, if not regenerate
    token = session[:jwt_token]
    if Token.expired?(token, ENV['JWT_SECRET'])
      token = Token.new(ENV['JWT_SECRET']).to_jwt
      session[:jwt_token] = token
    end

    # find correct BAM files
    if params[:whole_genome_search][:cell_lines].blank?
      unless @results.blank?
        @cell_lines = rank_cell_lines(@results)
      else
        @cell_lines = top_hits(@all_cnv_results, :cell_id, 4).flatten
      end
    else
      @cell_lines = parse_search_terms(:whole_genome_search, :cell_lines)
    end
    # gotcha to reformat names in case cell line has a slash in it, will break matching
    @cell_lines.map!{|cell_id| cell_id.gsub(/\//, '_')}
    cell_line_objs = CellLine.any_of({:sample_name.in => @cell_lines}, {:bam_sample_name.in => @cell_lines}).to_a.keep_if {|x| not x.hide}
    # gotcha in case no 'good' cell lines are found
    if @cell_lines.blank? && @results.blank?
      cell_line_objs = CellLine.where(sample_name: @all_cnv_results.first.cell_id).to_a
      @cell_lines = cell_line_objs.map(&:sample_name)
    elsif @cell_lines.blank? && @all_cnv_results.blank?
      cell_line_objs = CellLine.where(sample_name: @results.first.cell_id).to_a
      @cell_lines = cell_line_objs.map(&:sample_name)
    end
    cell_line_objs.each do |cell_line|
      @tracks << {
          headers: {
            'Authorization': "Bearer #{client.access_token['access_token']}"
          },
          url: "#{client.generate_api_url(cell_line[:bucket], cell_line[:bam_path])}",
          indexURL: "#{client.generate_api_url(cell_line[:bucket], cell_line[:bai_path])}",
          compression: 'NONE',
          name: "#{cell_line[:name]}",
          type: "alignment"
      }
    end

    # construct locus from first variant present in top cell line
    if !@results.blank?
      good = @results.select {|v| v.cell_id == @cell_lines.first && v.consequence == 'missense_variant'}
      # naturally sorting by snp_id will return lowest chrom & pos combination
      first_result = Naturally.sort_by(good, :snp_id).first
      if first_result.nil?
        first_result = @results.first
      end
      @locus = "chr#{first_result.chrom}:#{view_context.number_with_delimiter(first_result.pos - 250, delimiter: ',')}-#{view_context.number_with_delimiter(first_result.pos + 249, delimiter: ',')}"
    elsif !@all_cnv_results.blank?
      first_result = Naturally.sort_by(@all_cnv_results, :cnv_id).first
      @locus = "chr#{first_result.chrom}:#{view_context.number_with_delimiter(first_result.start, delimiter: ',')}-#{view_context.number_with_delimiter(first_result.end, delimiter: ',')}"
    else
      # if no matches are found, use gene (if provided), otherwise default to beginning of chr1.
      @locus = params[:whole_genome_search][:genes].blank? ? "chr1:1-20000" : params[:whole_genome_search][:genes].first
    end
  end

  def exome_search
    # make sure user hasn't requested too many cell lines
    if params[:exome_search][:cell_lines].any?
      cells = params[:exome_search][:cell_lines].first.split
      if cells.size > 4
        render :too_many_cell_lines and return
      end
    end

    # search for variants
    @query = sanitize_search(:exome_search)
    @results = ExomeSequenceVariant.where(@query).to_a

    # collect IGV tracks
    @tracks = [
        {
            url: '//s3.amazonaws.com/igv.broadinstitute.org/annotations/hg19/genes/gencode.v18.annotation.sorted.gtf.gz',
            indexURL: '//s3.amazonaws.com/igv.broadinstitute.org/annotations/hg19/genes/gencode.v18.annotation.sorted.gtf.gz.tbi',
            name: 'Gencode v18 Annotations GTF',
            format: 'gtf',
            displayMode: 'SQUISHED',
            visibilityWindow: 10000000
        }
    ]

    # fetch token, check if still valid, if not regenerate
    token = session[:jwt_token]
    if Token.expired?(token, ENV['JWT_SECRET'])
      token = Token.new(ENV['JWT_SECRET']).to_jwt
      session[:jwt_token] = token
    end

    # find correct BAM files
    if params[:exome_search][:cell_lines].blank?
      unless @results.blank?
        @cell_lines = rank_cell_lines(@results)
      end
    else
      @cell_lines = parse_search_terms(:exome_search, :cell_lines)
    end

    # gotcha to reformat names in case cell line has a slash in it, will break matching
    @cell_lines.map!{|cell_id| cell_id.gsub(/\//, '_')}
    cell_line_objs = ExomeCellLine.any_of({:name.in => @cell_lines}, {:bam_sample_name.in => @cell_lines}).to_a

    cell_line_objs.each do |cell_line|
      @tracks << {
          headers: {
            'Authorization': "Bearer #{client.access_token['access_token']}"
          },
          url: "#{client.generate_api_url(cell_line[:bucket], cell_line[:bam_path])}",
          indexURL: "#{client.generate_api_url(cell_line[:bucket], cell_line[:bai_path])}",
          compression: 'NONE',
          name: "#{cell_line[:name]}",
          type: "alignment"
      }
    end

    # construct locus from first variant present in top cell line
    if !@results.blank?
      good = @results.select {|v| v.cell_id == @cell_lines.first && v.consequence == 'missense_variant'}
      # naturally sorting by snp_id will return lowest chrom & pos combination
      first_result = Naturally.sort_by(good, :snp_id).first
      if first_result.nil?
        first_result = @results.first
      end
      @locus = "chr#{first_result.chrom}:#{view_context.number_with_delimiter(first_result.pos - 250, delimiter: ',')}-#{view_context.number_with_delimiter(first_result.pos + 249, delimiter: ',')}"
    else
      # if no matches are found, use gene (if provided), otherwise default to beginning of chr1.
      @locus = params[:exome_search][:genes].blank? ? "chr1:1-20000" : params[:exome_search][:genes].first
    end
  end

  # search genotype results and view data
  def genotype_search
    @query = sanitize_genotype_search
    @results = GenotypeVariant.where(@query).to_a
    if @results.blank?
      render :no_results, locals: {target: '#search-target'}
    else
      # format data for Plotly
      @genotype_data = Hash[params[:genotype_search][:genotypes].zip(params[:genotype_search][:genotypes].map{|n| {}})]
      if params[:genotype_search][:cell_lines].blank?
        @results.each do |result|
          if @genotype_data[result.genotype][result.variant].nil?
            @genotype_data[result.genotype][result.variant] = 1
          else
            @genotype_data[result.genotype][result.variant] += 1
          end
        end
      else
        @results.each do |result|
          if @genotype_data[result.genotype][result.cell_id].nil?
            @genotype_data[result.genotype][result.cell_id] = 1
          else
            @genotype_data[result.genotype][result.cell_id] += 1
          end
        end
      end
      # format data for circos
      raw_scatter = load_circos_data(@results, 'genotype')
      # create hash keyed by genotypes for storing results
      @scatter_results = Hash[params[:genotype_search][:genotypes].zip(params[:genotype_search][:genotypes].map{|n| {}})]
      @scatter_results.each_pair do |key,val|
        @scatter_results[key] = raw_scatter.select {|s| s[:des] == key}
      end
    end
  end

  # view precomputed heatmaps
  def view_precomputed_analysis
    @precomputed_heatmap = PrecomputedHeatmap.find(params[:precomputed_analysis][:id])
    # format data for plotly
    @data = [{
                 z: [],
                 x: @precomputed_heatmap.samples,
                 y: @precomputed_heatmap.features,
                 type: 'heatmap'
             }]
    @precomputed_heatmap.features.each_index do |feature_index|
      scores = []
      @precomputed_heatmap.samples.each_index do |sample_index|
        scores << @precomputed_heatmap.scores[sample_index][feature_index]
      end
      @data.first[:z] << scores
    end
  end

  # load circos structural data
  def view_circos_plots
    @lg_deletions_table = LargeCircosStructuralVariant.where(category: 'Deletion').to_a
    @lg_deletions_fixed = load_circos_data(@lg_deletions_table.select {|d| d.variant_type == 'Fixed'}, 'structural')
    @lg_deletions_mosaic = load_circos_data(@lg_deletions_table.select {|d| d.variant_type == 'Mosaic'}, 'structural')
    @lg_duplications_table = LargeCircosStructuralVariant.where(category: 'Duplication').to_a
    @lg_duplications_fixed = load_circos_data(@lg_duplications_table.select {|d| d.variant_type == 'Fixed'}, 'structural')
    @lg_duplications_mosaic = load_circos_data(@lg_duplications_table.select {|d| d.variant_type == 'Mosaic'}, 'structural')
    @lg_loh_table = LargeCircosStructuralVariant.where(category: 'CNN-LOH').to_a
    @lg_loh = load_circos_data(@lg_loh_table, 'structural')
  end

  def view_small_circos
    chrom = params[:small_circos_region][:chrom]
    category = params[:small_circos_region][:category]
    @chrom_index = SiteController::CHROMOSOMES.index(chrom)
    @table_data = SmallCircosStructuralVariant.where(gscn_category: category, chrom: chrom.to_s).to_a
    if @table_data.blank?
      render :no_results, locals: {target: '#sm-results-target'}
    else
      @sm_regions = load_circos_data(@table_data, 'structural')

      # gotcha in case all the values are the same, need to add a dummy region that has a val of 0
      if @table_data.map(&:gscn_min).uniq.size == 1
        @sm_regions << {chr: chrom, start: 0, end: 1, name: 'NOT DATA', value: 0}
      end
    end
  end

  def user_whitelist
    @whitelist_users = []
    Rails.logger.info "Current user: #{current_user.email}:#{current_user.admin}"
    UserWhitelist.all.each do |user|
      existing_user = User.find_by(email: user.email)
      @whitelist_users << [
          user.email,
          view_context.link_to_if(!existing_user.present? || !existing_user.admin?, "<i class='fa fa-fw fa-times'></i>".html_safe,
                               remove_user_from_whitelist_path(user.id), method: :delete,
                               class: 'btn btn-sm btn-danger delete-whitelist-user',
                               data: {remote: true}
          )
      ]
    end
    render json: {data: @whitelist_users}
  end

  def add_user_to_whitelist
    @user_whitelist = UserWhitelist.new(user_whitelist_params)
    @user_whitelist.save
  end

  def remove_user_from_whitelist
    user = UserWhitelist.find(params[:id])
    if user.present?
      user.destroy
    end
  end

  private

  # remove blank/empty search params that will break results
  # returns hash that can be used as a query across multiple fields
  def sanitize_search(search_key)
    query = {}
    params[search_key].each_pair do |key,val|
      terms = parse_search_terms(search_key, key)
      case key
        when 'genes'
          query[:searchable_symbol.in] = terms.map(&:downcase) unless terms.blank?
        when 'cell_lines'
          query[:cell_id.in] = terms unless terms.blank?
        when 'variants'
          query[:snp_id.in] = terms unless terms.blank?
      end
    end
    query
  end

  # sanitize method for genotype params
  def sanitize_genotype_search
    query = {}
    params[:genotype_search].each_pair do |key,val|
      terms = parse_search_terms(:genotype_search, key)
      case key
        when 'genotypes'
          query[:genotype.in] = terms unless terms.blank?
        when 'phenotype'
          query[:phenotype.in] = terms unless terms.blank?
        when 'cell_lines'
          query[:cell_id.in] = terms unless terms.blank?
        when 'variants'
          query[:variant.in] = terms unless terms.blank?
      end
    end
    query
  end

  # sanitize method for querying structural variants
  # variants query is handled differently as special range considerations apply, see whole_genome_search method
  def sanitize_structural_variant_search
    query = {}
    params[:whole_genome_search].each_pair do |key,val|
      terms = parse_search_terms(:whole_genome_search, key)
      case key
        when 'genes'
          query[:searchable_symbol.in] = terms.map(&:downcase) unless terms.blank?
        when 'cell_lines'
          query[:cell_id.in] = terms unless terms.blank?
      end
    end
    query
  end

  # generic search term parser, handles array autocomplete input as well as strings
  def parse_search_terms(root, key)
    if params[root][key].is_a?(Array)
      @list = params[root][key].delete_if(&:blank?).join(' ')
    else
      @list = params[root][key]
    end
    @list.split.map {|term| term.strip}
  end

  # necessary headers for viewing BAM files in IGV
  def cors_set_access_control_headers
    headers['Access-Control-Allow-Origin'] = '*'
    headers['Access-Control-Allow-Methods'] = 'GET,HEAD,PUT,POST,DELETE,OPTIONS'
    headers['Access-Control-Allow-Headers'] = 'RANGE,Content-Type,Authorization,X-Requested-With,Content-Length,Accept,Origin'
    headers['Access-Control-Expose-Headers'] = 'Content-Length'
  end

  # parse data into format for BioCircos
  def load_circos_data(results, type)
    data = []
    case type
      when 'sequence'
        results.each do |result|
          data << {chr: "#{result.chrom}", pos: "#{result.pos}", value: "#{result.hesc_af}" , des: "#{result.snp_id} (#{result.cell_id}:#{result.symbol}, #{result.consequence})", color: BIOCIRCOS_COLORS[result.chrom] }
        end
      when 'genotype'
        results.each do |result|
          vals = result.variant.split(':')
          chrom = vals.first
          position = vals.last
          data << {chr: "#{chrom}", start: "#{position}", end: "#{position.to_i + 1}", name: "#{result.cell_id}", des: "#{result.genotype}" }
        end
      when 'structural'
        results.each do |result|
          data << {chr: "#{result.chrom}", start: "#{result.start}", end: "#{result.end}", name: "#{result.is_a?(SmallCircosStructuralVariant) ? result.cnv_id : result.cell_id}", value: "#{result.is_a?(SmallCircosStructuralVariant) ? result.gscn_min : result.copy_number}" }
        end
    end
    data
  end

  # extract the 4 most informative cell lines by categorizing variants
  def rank_cell_lines(results)
    # select only missense variants that are in ClinVar
    if results.first.is_a?(SequenceVariant)
      good = results.select {|r| r.consequence == 'missense_variant' && r.clinvar_hit }
    end
    if good.blank?
      good = results.select {|r| r.consequence == 'missense_variant' }
    end
    # if we still don't have anything, just take the results
    if good.blank?
      good = results
    end
    # take the top cell line present
    top_hits(good, :cell_id, 4)
  end

  # helper to take top n groups by size
  def top_hits(results, key, amount)
    results.group_by(&key).sort_by { |group, results| -results.size}.take(amount).map(&:first)
  end

  # help email param whitelist
  def help_request_params
    params[:help_request].permit(:email, :subject, :content, :attachment, :captcha, :captcha_key)
  end

  def user_whitelist_params
    params[:user_whitelist].permit(:email)
  end
end
