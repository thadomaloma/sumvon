module PasswordFieldHelper
  # A password input with a show/hide button. Without JavaScript it is a plain password
  # field; password_visibility_controller reveals and drives the button.
  def password_field_with_toggle(form, attribute, data: {}, **options)
    input_id = form.field_id(attribute)
    show_label = t("auth.show_password")

    tag.div(class: "password-field", data: { controller: "password-visibility",
      password_visibility_show_label_value: show_label, password_visibility_hide_label_value: t("auth.hide_password") }) do
      safe_join([
        form.password_field(attribute, **options, class: [ "field password-input", options[:class] ],
          data: data.merge(password_visibility_target: "input")),
        tag.button(type: "button", hidden: true, class: "password-toggle", title: show_label,
          aria: { label: show_label, pressed: "false", controls: input_id },
          data: { password_visibility_target: "button", action: "mousedown->password-visibility#keepFocus click->password-visibility#toggle" }) do
          safe_join([
            heroicon(:eye, class: "size-5", data: { password_visibility_target: "showIcon" }),
            heroicon(:eye_slash, class: "size-5", hidden: true, data: { password_visibility_target: "hideIcon" })
          ])
        end
      ])
    end
  end
end
