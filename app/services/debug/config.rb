module Debug
  # Session defaults loaded once, at boot, from an optional `.cairnrc` file, so a
  # developer who always attaches to the same target doesn't retype host / port /
  # repo_path into the connect form every run. The values only pre-fill the form —
  # attaching is still an explicit click, so a stale target can't wedge boot.
  #
  # The file is YAML. Every key is optional:
  #
  #   host:      "127.0.0.1"                # target rdbg host
  #   port:      12345                       # target rdbg port
  #   repo_path: "/Users/you/code/my-app"    # the debuggee's source root
  #
  # Cairn runs in its own process and boots before it knows anything about the
  # target, so the file is looked up from where Cairn itself lives, not from the
  # debuggee. First path that exists wins:
  #
  #   1. $CAIRNRC               — explicit override (any path)
  #   2. <Rails.root>/.cairnrc  — beside the Cairn app
  #   3. ~/.cairnrc             — a personal default across projects
  class Config
    FILENAME = ".cairnrc".freeze
    DEFAULT_HOST = "127.0.0.1".freeze

    class << self
      # Read once and memoize: "on boot" means the file is not re-read on every
      # request. Restart Cairn (or pass reload: true) to pick up edits.
      def current = @current ||= new(locate)

      def reload = (@current = new(locate))

      # First candidate that points at a real file, or nil for none.
      def locate
        [ENV["CAIRNRC"].presence, root_path, home_path].compact.find { |path| File.file?(path) }
      end

      private

      def root_path = File.join(Rails.root, FILENAME)

      def home_path
        File.join(Dir.home, FILENAME)
      rescue ArgumentError
        nil # no HOME in the environment — skip the personal default
      end
    end

    attr_reader :path, :host, :port, :repo_path

    def initialize(path = nil)
      @path = path
      data = parse(path)
      @host = data["host"].presence&.to_s || DEFAULT_HOST
      @port = data["port"].presence&.to_s
      # Match Session.attach's normalization so the pre-filled value behaves
      # exactly as one typed by hand: a trailing slash would break path work.
      @repo_path = data["repo_path"].presence&.to_s&.strip&.chomp("/")
    end

    # True when the values came from a real file rather than built-in defaults.
    def loaded? = @path.present?

    private

    # A malformed .cairnrc should never take Cairn down — the form still works
    # with built-in defaults — so any parse trouble is logged and swallowed.
    def parse(path)
      return {} if path.blank?

      loaded = YAML.safe_load_file(path)
      unless loaded.is_a?(Hash)
        Rails.logger.warn("[Cairn] #{path} is not a YAML mapping — ignoring")
        return {}
      end

      loaded.transform_keys(&:to_s)
    rescue => e
      Rails.logger.warn("[Cairn] could not read #{path}: #{e.class}: #{e.message}")
      {}
    end
  end
end
