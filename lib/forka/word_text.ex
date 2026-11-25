defmodule Forka.WordText do
  @moduledoc """
  Pure text rules for dictionary words, shared by the `Forka.Words` and `Forka.Games`
  Contexts: normalization for distinctness (case and accents folded) and playability.
  """

  @doc """
  Normalizes dictionary word text for distinctness comparison by folding accents and
  diacritics, stripping non-letter/space/hyphen characters, collapsing repeated spaces
  and hyphens, trimming, and downcasing.
  """
  @spec normalize_text(String.t() | nil) :: String.t()
  def normalize_text(nil), do: ""

  def normalize_text(text) when is_binary(text) do
    text
    |> String.normalize(:nfd)
    |> String.replace(~r/[^\p{L}\s\-]+/u, "")
    |> String.replace(~r/\s{2,}/u, " ")
    |> String.replace(~r/-{2,}/u, "-")
    |> String.trim()
    |> String.downcase()
    |> String.normalize(:nfc)
  end

  @doc """
  Returns true when `text` contains at least one guessable letter after normalization.
  """
  @spec playable_text?(term()) :: boolean()
  def playable_text?(text) when is_binary(text) do
    text
    |> normalize_text()
    |> String.replace(~r/[\s\-]+/u, "")
    |> Kernel.!=("")
  end

  def playable_text?(_other), do: false
end
