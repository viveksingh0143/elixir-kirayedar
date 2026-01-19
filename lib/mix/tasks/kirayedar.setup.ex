defmodule Mix.Tasks.Kirayedar.Setup do
  alias Kirayedar.Utils
  use Mix.Task

  @shortdoc "Generates multi-tenancy infrastructure based on your preferred naming"

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
  - Whether to generate LiveViews
  """

  def run(_args) do
    Mix.shell().info("""
    #{IO.ANSI.cyan()}
    ╔═══════════════════════════════════════╗
    ║   Kirayedar Multi-Tenancy Setup         ║
    ╚═══════════════════════════════════════╝
    #{IO.ANSI.reset()}
    """)

    # 1. Gather User Preferences
    resource_raw_name =
      Utils.prompt("What do you want to call your tenant/organization?", "Tenant")

    use_binary_id = Mix.shell().yes?("Do you want to use binary_id (UUID)?")
    admin_host = Utils.prompt("What is your Admin Host?", "localhost")
    primary_domain = Utils.prompt("What is your primary domain?", "example.com")
    need_liveviews = Mix.shell().yes?("Do you want to generate LiveViews for CRUD?")

    app_name = Utils.app_name()
    app_module = Utils.app_module()
    naming = Utils.naming_conventions(resource_raw_name)

    # 2. Setup Assigns for Templates
    assigns = [
      app_name: app_name,
      app_module: app_module,
      resource: naming.singular,
      module: naming.module,
      table: naming.plural,
      use_binary_id: use_binary_id
    ]

    # 3. Define paths
    template_dir = Path.join([:code.priv_dir(:kirayedar), "templates", "kirayedar.setup"])
    migration_folder = "priv/repo/#{assigns[:resource]}_migrations"
    model_path = "lib/#{app_name}/#{assigns[:resource]}.ex"

    File.mkdir_p!(migration_folder)
    Mix.shell().info("Created #{migration_folder} directory...")

    # 4. Generate Model File
    Utils.generate_file_by_template(
      template_dir,
      "model.ex.eex",
      model_path,
      assigns
    )

    Mix.shell().info("✔ Generated Model at #{model_path}")

    # 5. Generate Migration File
    timestamp = Utils.now_timestamp()
    migration_path = "priv/repo/migrations/#{timestamp}_create_#{assigns[:table]}.exs"

    Utils.generate_file_by_template(
      template_dir,
      "migration.ex.eex",
      migration_path,
      assigns
    )

    Mix.shell().info("✔ Generated migration at #{migration_path}")

    # 6. Update Config
    update_config(
      admin_host,
      primary_domain,
      assigns[:resource],
      use_binary_id,
      app_name,
      app_module
    )

    # 7. Conditionally call the LiveView Generator
    if need_liveviews do
      Mix.shell().info("Triggering LiveView generation...")
      Mix.Tasks.Kirayedar.Gen.Live.run([])
    end

    # 8. Print summary
    print_summary(
      naming,
      admin_host,
      primary_domain,
      use_binary_id,
      migration_path,
      model_path,
      need_liveviews
    )
  end

  defp update_config(admin_host, primary_domain, resource, use_binary_id, app_name, app_module) do
    config_path = "config/config.exs"

    Application.put_env(:kirayedar, :admin_host, admin_host)
    Application.put_env(:kirayedar, :primary_domain, primary_domain)
    Application.put_env(:kirayedar, :tenant_resource, resource)
    Application.put_env(:kirayedar, :binary_id, use_binary_id)

    if File.exists?(config_path) do
      original_content = File.read!(config_path)

      new_config = """

      # Kirayedar Multi-Tenancy Configuration
      config :kirayedar,
        repo: #{app_module}.Repo,
        admin_host: "#{admin_host}",
        primary_domain: "#{primary_domain}",
        tenant_model: #{app_module}.#{Macro.camelize(resource)},
        tenant_resource: :#{resource},
        binary_id: #{use_binary_id}
      """

      if String.contains?(original_content, "config :kirayedar") do
        Mix.shell().info("Config for :kirayedar already exists. Skipping updates.")
      else
        pattern = ~r/import_config\s+"#\{config_env\(\)\}\.exs"/

        updated_content =
          if String.match?(original_content, pattern) do
            String.replace(original_content, pattern, "#{new_config}\n\\0")
          else
            original_content <> "\n" <> new_config
          end

        File.write!(config_path, updated_content)
        Mix.shell().info("✔ Updated config/config.exs")
      end
    else
      Mix.shell().error("Could not find config/config.exs")
    end
  end

  defp print_summary(
         naming,
         admin_host,
         primary_domain,
         use_binary_id,
         migration_path,
         model_path,
         need_liveviews
       ) do
    Mix.shell().info("""

    #{IO.ANSI.green()}✔ Kirayedar Setup Complete!#{IO.ANSI.reset()}

    #{IO.ANSI.yellow()}Summary:#{IO.ANSI.reset()}
    • Resource: :#{naming.singular}
    • Module: #{naming.module}
    • Table: #{naming.plural}
    • Admin Host: #{admin_host}
    • Primary Domain: #{primary_domain}
    • Binary ID: #{use_binary_id}
    • Migration Path: #{migration_path}
    • Model Path: #{model_path}
    #{if need_liveviews, do: "• LiveViews: Generated", else: ""}

    #{IO.ANSI.cyan()}Next Steps:#{IO.ANSI.reset()}

    1. Run migrations:
       mix ecto.migrate

    2. Add the Kirayedar.Plug to your endpoint (lib/my_app_web/endpoint.ex):
       plug Kirayedar.Plug

    3. Update your Repo to use Kirayedar.Repo (lib/my_app/repo.ex):
       use Kirayedar.Repo

    4. Create your first tenant:
       Kirayedar.create(MyApp.Repo, "acme_corp")

    #{IO.ANSI.magenta()}Documentation:#{IO.ANSI.reset()}
    • GitHub: https://github.com/yourusername/kirayedar
    • Docs: https://hexdocs.pm/kirayedar
    """)
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:ecto_sql, "~> 3.12"},
      {:plug, "~> 1.16"},
      {:postgrex, "~> 0.19", optional: true},
      {:myxql, "~> 0.7", optional: true},
      {:phoenix_live_view, "~> 1.0", optional: true},
      {:ex_doc, "~> 0.31", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev], runtime: false}
    ]
  end

  defp description do
    """
    Multi-tenancy library for Elixir/Phoenix with schema-based isolation
    (PostgreSQL Schemas or MySQL Databases). Lightweight, observable,
    with clean separation of concerns.
    """
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url
      },
      maintainers: ["Your Name"]
    ]
  end

  defp docs do
    [
      main: "Kirayedar",
      extras: ["README.md", "CHANGELOG.md"],
      source_ref: "v#{@version}",
      source_url: @source_url
    ]
  end
end
