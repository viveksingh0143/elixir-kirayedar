# Used by "mix format"
[
  # Specify which files to format
  inputs: [
    "{mix,.formatter}.exs",
    "{config,lib,test}/**/*.{ex,exs}",
    "priv/templates/**/*.{ex,exs,eex}"
  ],

  # Maximum line length (default is 98)
  line_length: 120,

  # Import dependencies for plugins (if using)
  import_deps: [:ecto, :ecto_sql, :phoenix],

  # Subdirectories that have their own .formatter.exs
  subdirectories: ["priv/*/migrations"]
]
