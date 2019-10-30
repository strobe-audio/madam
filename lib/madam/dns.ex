defmodule Madam.DNS do
  def encode_txt(values) do
    values
    |> Enum.map(fn
      {k, v} ->
        k = k |> to_string() |> String.downcase()
        to_charlist("#{k}=#{v}")
      k -> to_charlist(k)
    end)
    |> case do
      [] -> ['']
      data -> data
    end
  end

  def decode_txt(kvs) when is_list(kvs) do
    kvs
    |> Enum.reject(&(byte_size(&1) == 0))
    |> Enum.into(%{}, &split_txt_kv/1)
  end

  def split_txt_kv(kv) when is_list(kv) do
    kv
    |> to_string()
    |> split_txt_kv()
  end

  def split_txt_kv(kv) when is_binary(kv) do
    case :binary.split(kv, "=") do
      [k] ->
        {String.downcase(k), true}

      [k, v] ->
        {String.downcase(k), v}
    end
  end
end
