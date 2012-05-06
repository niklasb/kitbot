Sequel.migration do
  change do
    create_table(:stats) do
      String :channel, :null => false
      String :user, :null => false
      Date :date, :null => false
      Integer :characters, :null => false
      Integer :words, :null => false
      primary_key([:channel, :user, :date])
    end
  end
end
