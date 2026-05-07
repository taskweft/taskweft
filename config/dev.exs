import Config

config :snakepit, python_executable: Path.join([File.cwd!(), ".venv", "bin", "python3"])
