defmodule Madam.DNS do
  defprotocol Encoder do
    @spec encode(t()) :: tuple()
    def encode(t)
  end

  defmodule Msg do
    defstruct id: 0,
              ifname: nil,
              ifaddr: [],
              addr: nil,
              questions: [],
              answers: [],
              resources: [],
              type: :msg,
              aa: true,
              qr: true,
              opcode: :query

    defimpl Encoder do
      def encode(msg) do
        :inet_dns.make_msg(
          header: header(msg),
          anlist: rr(msg.answers),
          arlist: rr(msg.resources),
          qdlist: rr(msg.questions)
        )
      end

      defp header(msg) do
        :inet_dns.make_header(
          id: msg.id,
          qr: msg.qr,
          opcode: msg.opcode,
          aa: msg.aa,
          tc: false,
          rd: false,
          ra: false,
          pr: false,
          rcode: 0
        )
      end

      defp rr(rr) do
        Enum.map(rr, &Encoder.encode/1)
      end
    end
  end

  defmodule RR do
    defstruct [:type, :domain, :ttl, data: nil, class: :in, flush: true]

    def new(params) do
      struct(__MODULE__, params)
    end

    defimpl Encoder do
      def encode(rr) do
        # inet_dns uses `func` for flush for some kind of twisted historical reason
        # https://github.com/erlang/otp/blob/9834e606314df2c14970de9abeebdd7e3b14b505/lib/kernel/src/inet_dns.hrl#L224
        rr
        |> Map.from_struct()
        |> Enum.map(fn
          {:flush, flush?} -> {:func, flush?}
          kv -> kv
        end)
        |> Enum.reject(fn {_k, v} -> is_nil(v) end)
        |> :inet_dns.make_rr()
      end
    end
  end

  defmodule Query do
    @enforce_keys [:domain]
    defstruct [:domain, type: :a, class: :in, unicast_response: false]

    def new(params) do
      struct(__MODULE__, params)
    end

    defimpl Encoder do
      def encode(query) do
        :inet_dns.make_dns_query(
          class: query.class,
          type: query.type,
          domain: to_charlist(query.domain)
          # unicast_response: query.unicast_response
        )
      end
    end
  end

  def encode(msg) do
    msg
    |> Encoder.encode()
    |> :inet_dns.encode(_mdns = true)
  end

  def encode_txt(values) do
    values
    |> Enum.map(fn
      {k, v} ->
        k = k |> to_string() |> String.downcase()
        to_charlist("#{k}=#{v}")

      k ->
        to_charlist(k)
    end)
    |> case do
      [] -> [~c()]
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
