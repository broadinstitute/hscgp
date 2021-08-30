Rails.application.routes.draw do

	scope 'hscgp' do
		# authentication routes
		devise_for :users

		# autocomplete routes
		resources :genes, only: [:show, :index] do
			get :autocomplete_gene_symbol, on: :collection
		end
		resources :cell_lines, only: [:show, :index] do
			get :autocomplete_cell_line_sample_name, on: :collection
		end
		resources :exome_cell_lines, only: [:show, :index] do
			get :autocomplete_exome_cell_line_bam_sample_name, on: :collection
    end

    # admin actions
    get '/user_whitelist', to: 'site#user_whitelist', as: :user_whitelist
    post '/user_whitelist', to: 'site#add_user_to_whitelist', as: :add_user_to_whitelist
    delete '/user_whitelist/:id', to: 'site#remove_user_from_whitelist', as: :remove_user_from_whitelist

		# site actions
		post '/view_precomputed_analysis', to: 'site#view_precomputed_analysis', as: :view_precomputed_analysis
		post '/whole_genome_search', to: 'site#whole_genome_search', as: :whole_genome_search
		post '/exome_search', to: 'site#exome_search', as: :exome_search
		post '/genotype_search', to: 'site#genotype_search', as: :genotype_search
		post '/help_request', to: 'site#help_request', as: :help_request
		get '/view_circos_plots', to: 'site#view_circos_plots', as: :view_circos_plots
		post '/view_small_circos', to: 'site#view_small_circos', as: :view_small_circos
		get '/', to: 'site#index', as: :site
		root to: 'site#index'
	end
end
