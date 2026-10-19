module FormErrorsHelper
  # Inline error for one attribute, placed under its field and referenced by aria-describedby.
  def field_error_message(object, attribute)
    return unless object.errors.include?(attribute)

    tag.p(class: "field-error", id: field_error_id(object, attribute)) do
      safe_join([ heroicon(:exclamation_triangle, variant: :solid, class: "size-4 shrink-0"), tag.span(object.errors.full_messages_for(attribute).first) ])
    end
  end

  # aria attributes for a field: marks it invalid and links its error and any hint.
  def field_aria(object, attribute, hint_id: nil)
    invalid = object.errors.include?(attribute)
    describedby = [ hint_id, (field_error_id(object, attribute) if invalid) ].compact.join(" ").presence
    { invalid: (true if invalid), describedby: }.compact
  end

  def field_error_id(object, attribute)
    "#{object.model_name.param_key}_#{attribute}_error"
  end
end
