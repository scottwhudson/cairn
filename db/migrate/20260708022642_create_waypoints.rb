class CreateWaypoints < ActiveRecord::Migration[8.1]
  def change
    create_table :waypoints do |t|
      t.references :tour, null: false, foreign_key: true
      t.integer :position, null: false, default: 0
      t.string :file, null: false               # path relative to the tour's repo_path
      t.integer :line, null: false
      t.text :note                               # "why this changed" narrative
      t.string :condition                        # optional DAP conditional-breakpoint expression
      t.string :change_kind                      # "added" | "removed" | "modified" | nil
      t.string :author                           # "author" (shipped) | "reviewer" (ad hoc)

      t.timestamps
    end

    add_index :waypoints, [:tour_id, :position]
  end
end
