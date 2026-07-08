class CreateTraceRuns < ActiveRecord::Migration[8.1]
  def change
    create_table :trace_runs do |t|
      t.references :tour, foreign_key: true      # optional: a trace can stand alone
      t.string :label, null: false               # e.g. "before", "after"
      t.string :git_ref                          # ref the trace was recorded against
      t.string :entrypoint                       # the script that was traced
      # One event per element: {method,file,line,depth,event,locals}. Stored inline
      # per spec (jsonb) so two runs can be diffed without touching the filesystem.
      t.jsonb :events, null: false, default: []
      t.integer :event_count, null: false, default: 0

      t.timestamps
    end
  end
end
