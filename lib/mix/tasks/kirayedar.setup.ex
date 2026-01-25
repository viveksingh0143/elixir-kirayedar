defmodule Mix.Tasks.Kirayedar.Setup do
  @moduledoc """
  Generates the complete Kirayedar multi-tenancy setup for your application.

  This task will:
  - Generate the tenant model
  - Create the tenant table migration
  - Update your config.exs
  - Optionally generate LiveView CRUD

  ## Usage

      mix kirayedar.setup

  You will be prompted for:
  - Tenant resource name (e.g., "Tenant", "Organization")
  - Whether to use binary_id (UUID)
  - Admin host domain
  - Primary domain
  - Whether to generate LiveViews
  """

  use Mix.Task
  alias Kirayedar.Utils

  @shortdoc "Generates multi-tenancy infrastructure based on your preferred naming"

  @impl Mix.Task
  def run(_args) do
    print_header()

    # 1. Gather User Preferences
    preferences = gather_preferences()

    # 2. Setup configuration
    app_name = Utils.app_name()
    app_module = Utils.app_module()
    naming = Utils.naming_conventions(preferences.resource_name)

    # 3. Setup Assigns for Templates
    assigns = build_assigns(app_name, app_module, naming, preferences.use_binary_id)

    # 4. Generate files
    paths = generate_files(assigns)

    # 5. Update Config
    update_config(
      preferences.admin_host,
      preferences.primary_domain,
      assigns[:resource],
      preferences.use_binary_id,
      app_module
    )

    # 6. Conditionally generate LiveViews
    if preferences.generate_liveviews do
      Mix.shell().info("\n#{IO.ANSI.cyan()}Generating LiveView CRUD...#{IO.ANSI.reset()}")
      Mix.Tasks.Kirayedar.Gen.Live.run([])
    end

    # 7. Print summary
    print_summary(
      naming,
      preferences,
      paths,
      preferences.generate_liveviews,
      app_name
    )
  end

  # ============================================================================
  # Private Functions - User Input
  # ============================================================================

  defp print_header do
    Mix.shell().info("""
    #{IO.ANSI.cyan()}
    ╔═══════════════════════════════════════╗
    ║   Kirayedar Multi-Tenancy Setup       ║
    ╚═══════════════════════════════════════╝
    #{IO.ANSI.reset()}

    This wizard will help you set up multi-tenancy for your application.
    """)
  end

  defp gather_preferences do
    Mix.shell().info("#{IO.ANSI.yellow()}Configuration:#{IO.ANSI.reset()}")

    resource_name =
      Utils.prompt("What do you want to call your tenant/organization?", "Tenant")

    use_binary_id = Mix.shell().yes?("Do you want to use binary_id (UUID)?")

    admin_host = Utils.prompt("What is your Admin Host?", "localhost")

    primary_domain = Utils.prompt("What is your primary domain?", "example.com")

    generate_liveviews = Mix.shell().yes?("Do you want to generate LiveViews for CRUD?")

    Mix.shell().info("")

    %{
      resource_name: resource_name,
      use_binary_id: use_binary_id,
      admin_host: admin_host,
      primary_domain: primary_domain,
      generate_liveviews: generate_liveviews
    }
  end

  # ============================================================================
  # Private Functions - File Generation
  # ============================================================================

  defp build_assigns(app_name, app_module, naming, use_binary_id) do
    [
      app_name: app_name,
      app_module: app_module,
      resource: naming.singular,
      module: naming.module,
      table: naming.plural,
      use_binary_id: use_binary_id
    ]
  end

  defp generate_files(assigns) do
    template_dir = get_template_dir()

    # Create migration folder
    migration_folder = "priv/repo/#{assigns[:resource]}_migrations"
    File.mkdir_p!(migration_folder)

    Mix.shell().info(
      "#{IO.ANSI.green()}✓#{IO.ANSI.reset()} Created #{migration_folder} directory"
    )

    # Generate Model
    model_path = generate_model(template_dir, assigns)

    # Generate Migration
    migration_path = generate_migration(template_dir, assigns)

    %{
      model: model_path,
      migration: migration_path,
      migration_folder: migration_folder
    }
  end

  defp get_template_dir do
    Path.join([:code.priv_dir(:kirayedar), "templates", "kirayedar.setup"])
  end

  defp generate_model(template_dir, assigns) do
    model_path = "lib/#{assigns[:app_name]}/#{assigns[:resource]}.ex"

    Utils.generate_file_by_template(
      template_dir,
      "model.ex.eex",
      model_path,
      assigns
    )

    Mix.shell().info("#{IO.ANSI.green()}✓#{IO.ANSI.reset()} Generated Model at #{model_path}")

    model_path
  end

  defp generate_migration(template_dir, assigns) do
    timestamp = Utils.now_timestamp()
    migration_path = "priv/repo/migrations/#{timestamp}_create_#{assigns[:table]}.exs"

    Utils.generate_file_by_template(
      template_dir,
      "migration.ex.eex",
      migration_path,
      assigns
    )

    Mix.shell().info(
      "#{IO.ANSI.green()}✓#{IO.ANSI.reset()} Generated migration at #{migration_path}"
    )

    migration_path
  end

  # ============================================================================
  # Private Functions - Configuration
  # ============================================================================

  defp update_config(admin_host, primary_domain, resource, use_binary_id, app_module) do
    config_path = "config/config.exs"

    # Update Application environment for current session
    Application.put_env(:kirayedar, :admin_host, admin_host)
    Application.put_env(:kirayedar, :primary_domain, primary_domain)
    Application.put_env(:kirayedar, :tenant_resource, resource)
    Application.put_env(:kirayedar, :binary_id, use_binary_id)

    if File.exists?(config_path) do
      update_config_file(
        config_path,
        admin_host,
        primary_domain,
        resource,
        use_binary_id,
        app_module
      )
    else
      Mix.shell().error("#{IO.ANSI.red()}✗#{IO.ANSI.reset()} Could not find config/config.exs")
    end
  end

  defp update_config_file(
         config_path,
         admin_host,
         primary_domain,
         resource,
         use_binary_id,
         app_module
       ) do
    original_content = File.read!(config_path)

    if String.contains?(original_content, "config :kirayedar") do
      Mix.shell().info(
        "#{IO.ANSI.yellow()}!#{IO.ANSI.reset()} Config for :kirayedar already exists. Skipping config update."
      )
    else
      new_config =
        build_config_block(admin_host, primary_domain, resource, use_binary_id, app_module)

      updated_content = inject_config(original_content, new_config)

      File.write!(config_path, updated_content)
      Mix.shell().info("#{IO.ANSI.green()}✓#{IO.ANSI.reset()} Updated config/config.exs")
    end
  end

  defp build_config_block(admin_host, primary_domain, resource, use_binary_id, app_module) do
    """

    # Kirayedar Multi-Tenancy Configuration
    config :kirayedar,
      repo: #{app_module}.Repo,
      admin_host: "#{admin_host}",
      primary_domain: "#{primary_domain}",
      tenant_model: #{app_module}.#{Macro.camelize(resource)},
      tenant_resource: :#{resource},
      binary_id: #{use_binary_id}
    """
  end

  defp inject_config(original_content, new_config) do
    # Try to insert before import_config line
    pattern = ~r/import_config\s+"#\{config_env\(\)\}\.exs"/

    if String.match?(original_content, pattern) do
      String.replace(original_content, pattern, "#{new_config}\n\\0")
    else
      # If no import_config found, append to end
      original_content <> "\n" <> new_config
    end
  end

  # ============================================================================
  # Private Functions - Summary
  # ============================================================================

  defp print_summary(naming, preferences, paths, liveviews_generated, app_name) do
    Mix.shell().info("""

    #{IO.ANSI.green()}╔═══════════════════════════════════════╗
    ║   Setup Complete! 🎉                  ║
    ╚═══════════════════════════════════════╝#{IO.ANSI.reset()}

    #{IO.ANSI.yellow()}Configuration Summary:#{IO.ANSI.reset()}
    #{format_summary_line("Resource", ":#{naming.singular}")}
    #{format_summary_line("Module", naming.module)}
    #{format_summary_line("Table", naming.plural)}
    #{format_summary_line("Admin Host", preferences.admin_host)}
    #{format_summary_line("Primary Domain", preferences.primary_domain)}
    #{format_summary_line("Binary ID", preferences.use_binary_id)}
    #{format_summary_line("LiveViews", if(liveviews_generated, do: "Generated", else: "Not generated"))}

    #{IO.ANSI.yellow()}Generated Files:#{IO.ANSI.reset()}
    #{format_summary_line("Model", paths.model)}
    #{format_summary_line("Migration", paths.migration)}
    #{format_summary_line("Migration Folder", paths.migration_folder)}

    #{IO.ANSI.cyan()}╔═══════════════════════════════════════╗
    ║   Next Steps                          ║
    ╚═══════════════════════════════════════╝#{IO.ANSI.reset()}

    #{IO.ANSI.white()}1.#{IO.ANSI.reset()} #{IO.ANSI.bright()}Run migrations:#{IO.ANSI.reset()}
       #{IO.ANSI.cyan()}mix ecto.migrate#{IO.ANSI.reset()}

    #{IO.ANSI.white()}2.#{IO.ANSI.reset()} #{IO.ANSI.bright()}Add Kirayedar.Plug to your endpoint:#{IO.ANSI.reset()}
       #{IO.ANSI.faint()}# lib/#{app_name}_web/endpoint.ex#{IO.ANSI.reset()}
       #{IO.ANSI.green()}plug Kirayedar.Plug#{IO.ANSI.reset()}

    #{IO.ANSI.white()}3.#{IO.ANSI.reset()} #{IO.ANSI.bright()}Update your Repo:#{IO.ANSI.reset()}
       #{IO.ANSI.faint()}# lib/#{app_name}/repo.ex#{IO.ANSI.reset()}
       #{IO.ANSI.green()}use Kirayedar.Repo#{IO.ANSI.reset()}

    #{IO.ANSI.white()}4.#{IO.ANSI.reset()} #{IO.ANSI.bright()}Create your first tenant:#{IO.ANSI.reset()}
       #{IO.ANSI.cyan()}iex> alias #{naming.module}
       iex> alias MyApp.Repo

       # Create tenant record
       iex> tenant = %#{naming.module}{name: "Acme Corp", slug: "acme_corp"}
                     |> #{naming.module}.changeset(%{})
                     |> Repo.insert!()

       # Create schema and run migrations
       iex> Kirayedar.create_and_migrate(Repo, tenant.slug)
       :ok#{IO.ANSI.reset()}
    #{if liveviews_generated, do: print_liveview_routes(naming, app_name), else: ""}
    #{IO.ANSI.magenta()}╔═══════════════════════════════════════╗
    ║   Documentation & Support             ║
    ╚═══════════════════════════════════════╝#{IO.ANSI.reset()}

    #{format_summary_line("GitHub", "https://github.com/viveksingh0143/elixir-kirayedar")}
    #{format_summary_line("Hex Docs", "https://hexdocs.pm/kirayedar")}
    #{format_summary_line("Issues", "https://github.com/viveksingh0143/elixir-kirayedar/issues")}

    #{IO.ANSI.green()}Happy multi-tenanting! 🚀#{IO.ANSI.reset()}
    """)
  end

  defp print_liveview_routes(naming, app_name) do
    """

    #{IO.ANSI.white()}5.#{IO.ANSI.reset()} #{IO.ANSI.bright()}Add routes for LiveViews:#{IO.ANSI.reset()}
       #{IO.ANSI.faint()}# lib/#{app_name}_web/router.ex#{IO.ANSI.reset()}
       #{IO.ANSI.green()}scope "/", YourAppWeb do
         pipe_through :browser

         live "/#{naming.plural}", #{naming.module}Live.Index, :index
         live "/#{naming.plural}/new", #{naming.module}Live.Index, :new
         live "/#{naming.plural}/:id/edit", #{naming.module}Live.Index, :edit

         live "/#{naming.plural}/:id", #{naming.module}Live.Show, :show
         live "/#{naming.plural}/:id/show/edit", #{naming.module}Live.Show, :edit
       end#{IO.ANSI.reset()}
    """
  end

  defp format_summary_line(label, value) do
    "    #{IO.ANSI.white()}•#{IO.ANSI.reset()} #{String.pad_trailing(label <> ":", 20)} #{IO.ANSI.cyan()}#{value}#{IO.ANSI.reset()}"
  end
end
