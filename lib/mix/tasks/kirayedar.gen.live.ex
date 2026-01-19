defmodule Mix.Tasks.Kirayedar.Gen.Live do
  use Mix.Task
  alias Kirayedar.Utils

  @shortdoc "Generate LiveView CRUD for your tenant resource"

  @moduledoc """
  Generates LiveView components for tenant management.

  This task generates:
  - Index LiveView with list and actions
  - Form component for create/update
  - Show LiveView for viewing details

  ## Usage

      mix kirayedar.gen.live

  Note: This requires that you've already run `mix kirayedar.setup`
  """

  def run(_args) do
    resource = Utils.get_config_or_fail(:tenant_resource)
    naming = Utils.naming_conventions(resource)
    app_name = Utils.app_name()
    app_module = Utils.app_module()

    assigns = [
      app_name: app_name,
      app_module: app_module,
      module: naming.module,
      singular: naming.singular,
      plural: naming.plural
    ]

    template_dir = Path.join([:code.priv_dir(:kirayedar), "templates", "kirayedar.gen.live"])
    target_path = "lib/#{app_name}_web/live/#{naming.singular}_live"

    File.mkdir_p!(target_path)

    # Generate Index LiveView
    list_path = "#{target_path}/index.ex"

    Utils.generate_file_by_template(
      template_dir,
      "index.ex.eex",
      list_path,
      assigns
    )

    Mix.shell().info("✔ Generated LiveView Index at #{target_path}/index.ex")

    # Generate Form Component
    form_path = "#{target_path}/form_component.ex"

    Utils.generate_file_by_template(
      template_dir,
      "form_component.ex.eex",
      form_path,
      assigns
    )

    Mix.shell().info("✔ Generated LiveView FormComponent at #{target_path}/form_component.ex")

    # Generate Show LiveView
    show_path = "#{target_path}/show.ex"

    Utils.generate_file_by_template(
      template_dir,
      "show.ex.eex",
      show_path,
      assigns
    )

    Mix.shell().info("✔ Generated LiveView Show at #{target_path}/show.ex")

    print_summary(app_name, app_module, naming, list_path, form_path, show_path)
  end

  defp print_summary(app_name, app_module, naming, list_path, form_path, show_path) do
    Mix.shell().info("""

    #{IO.ANSI.green()}✔ LiveView Generation Complete!#{IO.ANSI.reset()}

    #{IO.ANSI.yellow()}Summary:#{IO.ANSI.reset()}
    • Index: #{list_path}
    • Form: #{form_path}
    • Show: #{show_path}

    #{IO.ANSI.magenta()}Next Step: Add routes to your lib/#{app_name}_web/router.ex:#{IO.ANSI.reset()}

    scope "/", #{app_module}Web do
      pipe_through :browser

      live "/#{naming.plural}", #{naming.module}Live.Index, :index
      live "/#{naming.plural}/new", #{naming.module}Live.Index, :new
      live "/#{naming.plural}/:id/edit", #{naming.module}Live.Index, :edit

      live "/#{naming.plural}/:id", #{naming.module}Live.Show, :show
      live "/#{naming.plural}/:id/show/edit", #{naming.module}Live.Show, :edit
    end
    """)
  end
end
