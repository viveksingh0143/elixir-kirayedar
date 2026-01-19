defmodule Kirayedar.Utils do
  import Mix.Generator
  @moduledoc false

  @doc "Detects the current project name as a string (e.g., 'my_app')"
  def app_name do
    to_string(Mix.Project.config()[:app])
  end

  @doc "Detects the current project module as a string (e.g., 'MyApp')"
  def app_module do
    app_name() |> Macro.camelize()
  end

  @doc "Simple rule-based pluralizer"
  def pluralize(word) do
    word = String.downcase(word)

    cond do
      # Case: ends in "y" but not "ay", "ey", etc.
      String.ends_with?(word, "y") and
          not String.ends_with?(word, ["ay", "ey", "iy", "oy", "uy"]) ->
        String.slice(word, 0..-2//1) <> "ies"

      # Case: ends in s, x, z, ch, sh
      String.ends_with?(word, ["s", "x", "z", "ch", "sh"]) ->
        word <> "es"

      # Default case
      true ->
        word <> "s"
    end
  end

  @doc """
  Generates singular, plural, and module names from a raw string or atom.
  Returns a Map.
  """
  def naming_conventions(raw_name) when is_atom(raw_name) do
    naming_conventions(to_string(raw_name))
  end

  def naming_conventions(raw_name) when is_binary(raw_name) do
    singular = String.downcase(String.trim(raw_name))

    %{
      singular: singular,
      plural: pluralize(singular),
      module: Macro.camelize(singular)
    }
  end

  @doc "Generates a timestamp for migrations: YYYYMMDDHHMMSS"
  def now_timestamp do
    {{y, m, d}, {hh, mm, ss}} = :calendar.local_time()
    "#{y}#{pad(m)}#{pad(d)}#{pad(hh)}#{pad(mm)}#{pad(ss)}"
  end

  @doc "Smart prompt that loops until a value is provided"
  def prompt_required(question) do
    answer = Mix.shell().prompt("#{question}:") |> String.trim()

    if answer == "" do
      Mix.shell().error("Error: This field is required.")
      prompt_required(question)
    else
      answer
    end
  end

  @doc "Smart prompt with a default value in brackets"
  def prompt(question, default) do
    answer = Mix.shell().prompt("#{question} [#{default}]:") |> String.trim()
    if answer == "", do: default, else: answer
  end

  @doc "get config using key or stop task processing"
  def get_config_or_fail(key) do
    case Application.get_env(:kirayedar, key) do
      nil ->
        Mix.shell().error("Missing config [:kirayedar, :#{key}]. Run 'mix kirayedar.setup'.")
        System.halt(1)

      value ->
        value
    end
  end

  @doc "generate template file by assigns"
  def generate_file_by_template(dir, source, target, assigns) do
    content = EEx.eval_file(Path.join(dir, source), assigns: assigns)
    create_file(target, content)
  end

  defp pad(n), do: String.pad_leading("#{n}", 2, "0")
end
