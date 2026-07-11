# Read the optional .cairnrc session defaults once, at boot, and note in the log
# where they came from — so the server output makes plain which target the
# connect form will pre-fill (or that no file was found).
Rails.application.config.after_initialize do
  config = Debug::Config.current
  if config.loaded?
    Rails.logger.info("[Cairn] session defaults loaded from #{config.path}")
  end
end
