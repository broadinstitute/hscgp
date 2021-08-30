module SiteHelper

	def render_boolean_field(field)
		if field
			"<span class='fa fa-check text-success'></span>".html_safe
		else
			"<span class='fa fa-times text-danger'></span>".html_safe
		end
	end

	def tooltip_truncate(attr)
		length = 15
		if attr.size > length
			"#{truncate(attr, length: length)} <span class='fa fa-plus-circle' title='#{attr}' data-toggle='tooltip' data-placement='right'></span><span class='hidden'>#{attr}</span>".html_safe
		else
			attr
		end
	end
end
