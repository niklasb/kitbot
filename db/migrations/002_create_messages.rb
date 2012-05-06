Sequel.migration do
  change do
    create_table(:messages) do
      String :channel, :null => false
      String :user, :null => false
      Time :time, :null => false
      Text :message, :null => false
    end
  end
end
