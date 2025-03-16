# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     MyApp.Repo.insert!(%MyApp.SomeSchema{})
#
# We recommend using the bang functions (`insert!`, `update!`
# and so on) as they will fail if something goes wrong.

# Read words-pt.csv file
require Logger

Logger.info("Starting to seed Portuguese words from CSV...")

words_pt_path =
  __ENV__.file
  |> Path.dirname()
  |> Path.join("seeds/words-pt.csv")

words_en_path =
  __ENV__.file
  |> Path.dirname()
  |> Path.join("seeds/words-en.csv")

pt_words =
  File.stream!(words_pt_path, [read_ahead: 100_000], 1000)
  |> Stream.filter(fn row ->
    row && String.trim(row) != ""
  end)
  |> CSV.decode!(headers: true)
  |> Enum.to_list()

en_words =
  File.stream!(words_en_path, [read_ahead: 100_000], 1000)
  |> Stream.filter(fn row ->
    row && String.trim(row) != ""
  end)
  |> CSV.decode!(headers: true)
  |> Enum.to_list()

{:ok, inserted_pt_words} = Forka.Words.import_words(pt_words)
{:ok, inserted_english_words} = Forka.Words.import_words(en_words)

# Get unique categories from Portuguese words
pt_categories = pt_words |> Enum.map(& &1["category"]) |> Enum.uniq() |> length()
en_categories = en_words |> Enum.map(& &1["category"]) |> Enum.uniq() |> length()

Logger.info(
  "Inserted #{length(inserted_pt_words)} Portuguese words across #{pt_categories} categories"
)

Logger.info(
  "Inserted #{length(inserted_english_words)} English words across #{en_categories} categories"
)

Logger.info("Total: #{length(inserted_pt_words) + length(inserted_english_words)} words inserted")
