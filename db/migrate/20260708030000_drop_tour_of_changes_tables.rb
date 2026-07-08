class DropTourOfChangesTables < ActiveRecord::Migration[8.1]
  # The app is now debugger-only: it attaches to a live rdbg DAP server and steps
  # through frames in memory. The "Tour of changes" persistence (tours, their
  # waypoints, and recorded trace runs) no longer bears any load, so drop it.
  def up
    drop_table :waypoints
    drop_table :trace_runs
    drop_table :tours
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
