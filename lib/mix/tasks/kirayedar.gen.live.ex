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

  ## What it generates

  Given a tenant resource named "Organization", it will generate:

  - `lib/my_app_web/live/organization_live/index.ex` - List all organizations
  - `lib/my_app_web/live/organization_live/form_component.ex` - Form for create/edit
  - `lib/my_app_web/live/organization_live/show.ex` - Show organization details

  ## Requirements

  Before running this task:
  1. Run `mix kirayedar.setup` first
  2. The templates must exist in `priv/templates/kirayedar.gen.live/`

  ## Examples

      # Generate LiveViews for your tenant model
      mix kirayedar.gen.live

      # After generation, add routes to your router:
      live "/organizations", OrganizationLive.Index, :index
      live "/organizations/new", OrganizationLive.Index, :new
      live "/organizations/:id/edit", OrganizationLive.Index, :edit
      live "/organizations/:id", OrganizationLive.Show, :show
      live "/organizations/:id/show/edit", OrganizationLive.Show, :edit
  """

  @impl Mix.Task
  def run(_args) do
    # Get tenant resource from config (set by kirayedar.setup)
    resource = Utils.get_config_or_fail(:tenant_resource)
    naming = Utils.naming_conventions(resource)
    app_name = Utils.app_name()
    app_module = Utils.app_module()

    # Build assigns for templates
    assigns = [
      app_name: app_name,
      app_module: app_module,
      module: naming.module,
      singular: naming.singular,
      plural: naming.plural
    ]

    # Get template directory
    template_dir = Path.join([:code.priv_dir(:kirayedar), "templates", "kirayedar.gen.live"])

    # Create target directory for LiveViews
    target_path = "lib/#{app_name}_web/live/#{naming.singular}_live"
    File.mkdir_p!(target_path)

    Mix.shell().info("\n#{IO.ANSI.cyan()}Generating LiveView files...#{IO.ANSI.reset()}\n")

    # Generate Index LiveView
    list_path = "#{target_path}/index.ex"

    Utils.generate_file_by_template(
      template_dir,
      "index.ex.eex",
      list_path,
      assigns
    )

    Mix.shell().info("#{IO.ANSI.green()}✔#{IO.ANSI.reset()} Generated LiveView Index at #{list_path}")

    # Generate Form Component
    form_path = "#{target_path}/form_component.ex"

    Utils.generate_file_by_template(
      template_dir,
      "form_component.ex.eex",
      form_path,
      assigns
    )

    Mix.shell().info("#{IO.ANSI.green()}✔#{IO.ANSI.reset()} Generated LiveView FormComponent at #{form_path}")

    # Generate Show LiveView
    show_path = "#{target_path}/show.ex"

    Utils.generate_file_by_template(
      template_dir,
      "show.ex.eex",
      show_path,
      assigns
    )

    Mix.shell().info("#{IO.ANSI.green()}✔#{IO.ANSI.reset()} Generated LiveView Show at #{show_path}")

    # Print summary with next steps
    print_summary(app_name, app_module, naming, list_path, form_path, show_path)
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp print_summary(app_name, app_module, naming, list_path, form_path, show_path) do
    Mix.shell().info("""

    #{IO.ANSI.green()}╔═══════════════════════════════════════╗
    ║   LiveView Generation Complete! ✨    ║
    ╚═══════════════════════════════════════╝#{IO.ANSI.reset()}

    #{IO.ANSI.yellow()}Generated Files:#{IO.ANSI.reset()}
    #{format_file_line("Index LiveView", list_path)}
    #{format_file_line("Form Component", form_path)}
    #{format_file_line("Show LiveView", show_path)}

    #{IO.ANSI.cyan()}╔═══════════════════════════════════════╗
    ║   Next Steps                          ║
    ╚═══════════════════════════════════════╝#{IO.ANSI.reset()}

    #{IO.ANSI.white()}1.#{IO.ANSI.reset()} #{IO.ANSI.bright()}Add routes to your router#{IO.ANSI.reset()}
       #{IO.ANSI.faint()}# lib/#{app_name}_web/router.ex#{IO.ANSI.reset()}

       #{IO.ANSI.green()}scope "/", #{app_module}Web do
         pipe_through :browser

         live "/#{naming.plural}", #{naming.module}Live.Index, :index
         live "/#{naming.plural}/new", #{naming.module}Live.Index, :new
         live "/#{naming.plural}/:id/edit", #{naming.module}Live.Index, :edit

         live "/#{naming.plural}/:id", #{naming.module}Live.Show, :show
         live "/#{naming.plural}/:id/show/edit", #{naming.module}Live.Show, :edit
       end#{IO.ANSI.reset()}

    #{IO.ANSI.white()}2.#{IO.ANSI.reset()} #{IO.ANSI.bright()}Visit your application#{IO.ANSI.reset()}
       Navigate to #{IO.ANSI.cyan()}http://localhost:4000/#{naming.plural}#{IO.ANSI.reset()} to manage tenants

    #{IO.ANSI.white()}3.#{IO.ANSI.reset()} #{IO.ANSI.bright()}Customize the templates#{IO.ANSI.reset()}
       Edit the generated LiveView files to match your application's needs

    #{IO.ANSI.green()}All set! Your tenant management UI is ready. 🚀#{IO.ANSI.reset()}
    """)
  end

  defp format_file_line(label, path) do
    "    #{IO.ANSI.white()}•#{IO.ANSI.reset()} #{String.pad_trailing(label <> ":", 20)} #{IO.ANSI.cyan()}#{path}#{IO.ANSI.reset()}"
  end
end
