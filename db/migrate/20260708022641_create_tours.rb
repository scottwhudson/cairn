class CreateTours < ActiveRecord::Migration[8.1]
  def change
    create_table :tours do |t|
      t.string :title, null: false
      t.text :description
      # Where the debuggee lives + how to launch it, so a session can be started.
      t.string :repo_path, null: false
      t.string :entrypoint, null: false        # e.g. "script/sample_app/run.rb"
      t.string :git_ref                          # branch/sha the tour was authored against
      t.string :status, null: false, default: "idle"

      t.timestamps
    end
  end
end
