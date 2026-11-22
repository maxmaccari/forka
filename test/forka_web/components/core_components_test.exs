defmodule ForkaWeb.CoreComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest
  import ForkaWeb.CoreComponents

  alias Phoenix.Component

  describe "button/1" do
    test "renders variants, sizes, full width, and disabled state" do
      for variant <- ~w(primary secondary link danger danger-link ghost),
          size <- ~w(sm md lg) do
        html =
          render_component(&button/1, %{
            variant: variant,
            size: size,
            full: true,
            disabled: true,
            inner_block: [%{__slot__: :inner_block, inner_block: fn _, _ -> "Enviar" end}]
          })

        doc = LazyHTML.from_fragment(html)
        btn = LazyHTML.query(doc, "button")
        assert Enum.count(btn) == 1
        assert LazyHTML.text(btn) =~ "Enviar"
        assert LazyHTML.attribute(btn, "disabled") == [""]
        assert hd(LazyHTML.attribute(btn, "class")) =~ "w-full"
      end
    end

    test "renders an anchor link when navigate is provided" do
      html =
        render_component(&button/1, %{
          navigate: "/salas",
          inner_block: [%{__slot__: :inner_block, inner_block: fn _, _ -> "Salas" end}]
        })

      doc = LazyHTML.from_fragment(html)
      link = LazyHTML.query(doc, "a")
      assert LazyHTML.attribute(link, "href") == ["/salas"]
      assert LazyHTML.text(link) =~ "Salas"
    end
  end

  describe "icon_button/1" do
    test "renders accessible button and link variants" do
      btn_html =
        render_component(&icon_button/1, %{
          icon: "hero-arrow-left",
          aria_label: "Voltar"
        })

      btn_doc = LazyHTML.from_fragment(btn_html)
      assert LazyHTML.attribute(LazyHTML.query(btn_doc, "button"), "aria-label") == ["Voltar"]

      link_html =
        render_component(&icon_button/1, %{
          icon: "hero-arrow-left",
          aria_label: "Voltar",
          navigate: "/salas"
        })

      link_doc = LazyHTML.from_fragment(link_html)
      assert LazyHTML.attribute(LazyHTML.query(link_doc, "a"), "aria-label") == ["Voltar"]
      assert LazyHTML.attribute(LazyHTML.query(link_doc, "a"), "href") == ["/salas"]
    end
  end

  describe "input/1" do
    test "renders text, email, password, checkbox, select, textarea, hint, and errors" do
      for type <- ~w(text email password) do
        html =
          render_component(&input/1, %{
            id: "field-#{type}",
            name: "player[#{type}]",
            type: type,
            label: "Campo #{type}",
            hint: "Dica útil",
            value: "valor"
          })

        doc = LazyHTML.from_fragment(html)
        input_el = LazyHTML.query(doc, "input")
        assert LazyHTML.attribute(input_el, "type") == [type]
        assert hd(LazyHTML.attribute(input_el, "class")) =~ "ring-line-strong"
        assert hd(LazyHTML.attribute(input_el, "class")) =~ "focus:ring-brand-ink"
        assert LazyHTML.text(doc) =~ "Dica útil"
      end

      err_html =
        render_component(&input/1, %{
          id: "field-err",
          name: "player[email]",
          type: "email",
          label: "Email",
          hint: "Oculta quando há erro",
          errors: ["não pode ficar em branco"],
          value: ""
        })

      err_doc = LazyHTML.from_fragment(err_html)
      assert LazyHTML.text(err_doc) =~ "não pode ficar em branco"
      refute LazyHTML.text(err_doc) =~ "Oculta quando há erro"

      cb_html =
        render_component(&input/1, %{
          id: "field-cb",
          name: "player[remember]",
          type: "checkbox",
          label: "Lembrar",
          value: true
        })

      assert LazyHTML.attribute(
               LazyHTML.query(LazyHTML.from_fragment(cb_html), "input[type=checkbox]"),
               "checked"
             ) == [""]

      sel_html =
        render_component(&input/1, %{
          id: "field-sel",
          name: "room[lang]",
          type: "select",
          label: "Idioma",
          prompt: "Escolha",
          options: [{"Português", "pt-BR"}, {"English", "en"}],
          value: "pt-BR"
        })

      sel_doc = LazyHTML.from_fragment(sel_html)
      assert LazyHTML.text(sel_doc) =~ "Português"

      assert hd(LazyHTML.attribute(LazyHTML.query(sel_doc, "select"), "class")) =~
               "ring-line-strong"

      ta_html =
        render_component(&input/1, %{
          id: "field-ta",
          name: "room[note]",
          type: "textarea",
          label: "Nota",
          value: "Olá"
        })

      ta_doc = LazyHTML.from_fragment(ta_html)
      ta_el = LazyHTML.query(ta_doc, "textarea")
      assert LazyHTML.text(ta_el) =~ "Olá"
      assert hd(LazyHTML.attribute(ta_el, "class")) =~ "ring-line-strong"
    end

    test "renders from a Phoenix.HTML.FormField" do
      form = Component.to_form(%{"name" => "Lia"}, as: :player)

      html =
        render_component(&input/1, %{
          field: form[:name],
          label: "Nome"
        })

      doc = LazyHTML.from_fragment(html)
      assert LazyHTML.attribute(LazyHTML.query(doc, "input"), "value") == ["Lia"]
    end
  end

  describe "switch/1 and segmented_control/1" do
    test "switch renders role=switch, aria-checked, label, and description" do
      html =
        render_component(&switch/1, %{
          id: "sound-switch",
          checked: true,
          label: "Sons do jogo",
          description: "Tocar efeitos sonoros"
        })

      doc = LazyHTML.from_fragment(html)
      sw = LazyHTML.query(doc, "[role=switch]")
      assert LazyHTML.attribute(sw, "aria-checked") == ["true"]
      assert LazyHTML.attribute(sw, "aria-labelledby") == ["sound-switch-label"]
      assert LazyHTML.text(doc) =~ "Sons do jogo"
      assert LazyHTML.text(doc) =~ "Tocar efeitos sonoros"
    end

    test "segmented_control renders radiogroup and radio options" do
      html =
        render_component(&segmented_control/1, %{
          id: "lang-seg",
          label: "Idioma",
          value: "pt",
          cols: 2,
          on_select: "set_lang",
          options: [{"pt", "PT-BR"}, {"en", "EN"}]
        })

      doc = LazyHTML.from_fragment(html)
      group = LazyHTML.query(doc, "[role=radiogroup]")
      assert LazyHTML.attribute(group, "aria-label") == ["Idioma"]
      assert LazyHTML.attribute(group, "phx-hook") == ["SegmentedControl"]
      radios = LazyHTML.query(doc, "[role=radio]")
      assert Enum.count(radios) == 2
      assert LazyHTML.attribute(radios, "aria-checked") == ["true", "false"]
      assert LazyHTML.attribute(radios, "tabindex") == ["0", "-1"]

      unmatched_html =
        render_component(&segmented_control/1, %{
          id: "lang-seg-empty",
          label: "Idioma",
          value: "es",
          options: [{"pt", "PT-BR"}, {"en", "EN"}]
        })

      unmatched_radios = LazyHTML.query(LazyHTML.from_fragment(unmatched_html), "[role=radio]")
      assert LazyHTML.attribute(unmatched_radios, "tabindex") == ["0", "-1"]
    end
  end

  describe "card/1, chip/1, badge/1, avatar/1" do
    test "card renders article with aria-labelledby and slots" do
      html =
        render_component(&card/1, %{
          id: "room-card",
          bordered: true,
          badge: [%{__slot__: :badge, inner_block: fn _, _ -> "Aberta" end}],
          title: [%{__slot__: :title, inner_block: fn _, _ -> "Sala 1" end}],
          meta: [%{__slot__: :meta, inner_block: fn _, _ -> "2/6" end}],
          inner_block: [%{__slot__: :inner_block, inner_block: fn _, _ -> "Corpo" end}],
          actions: [%{__slot__: :actions, inner_block: fn _, _ -> "Entrar" end}]
        })

      doc = LazyHTML.from_fragment(html)
      article = LazyHTML.query(doc, "article")
      assert LazyHTML.attribute(article, "aria-labelledby") == ["room-card-title"]
      assert LazyHTML.text(article) =~ "Sala 1"
      assert LazyHTML.text(article) =~ "Entrar"
    end

    test "chip sets aria-pressed" do
      html =
        render_component(&chip/1, %{
          pressed: true,
          inner_block: [%{__slot__: :inner_block, inner_block: fn _, _ -> "Animais" end}]
        })

      btn = LazyHTML.query(LazyHTML.from_fragment(html), "button")
      assert LazyHTML.attribute(btn, "aria-pressed") == ["true"]
    end

    test "badge renders all tones with optional icon" do
      for tone <- ~w(neutral brand accent success warning danger) do
        html =
          render_component(&badge/1, %{
            tone: tone,
            icon: "hero-check-circle-micro",
            inner_block: [%{__slot__: :inner_block, inner_block: fn _, _ -> tone end}]
          })

        assert LazyHTML.text(LazyHTML.from_fragment(html)) =~ tone
      end
    end

    test "avatar renders player colors 1..6, sizes, and eliminated state" do
      for idx <- 1..6, size <- ~w(xs sm md lg) do
        html = render_component(&avatar/1, %{name: "Bruno", player_index: idx, size: size})
        doc = LazyHTML.from_fragment(html)
        span = LazyHTML.query(doc, "span")
        assert LazyHTML.text(span) =~ "B"
        assert hd(LazyHTML.attribute(span, "class")) =~ "bg-player-#{idx}"
      end

      elim_html = render_component(&avatar/1, %{initial: "a", eliminated: true})
      elim_span = LazyHTML.query(LazyHTML.from_fragment(elim_html), "span")
      assert LazyHTML.text(elim_span) =~ "A"
      assert hd(LazyHTML.attribute(elim_span, "class")) =~ "bg-sunken"
    end
  end

  describe "overlays, feedback, and data components" do
    test "modal and bottom_sheet support dialog and alertdialog roles" do
      modal_html =
        render_component(&modal/1, %{
          id: "m1",
          show: true,
          role: "alertdialog",
          title: [%{__slot__: :title, inner_block: fn _, _ -> "Desistir?" end}],
          description: [
            %{__slot__: :description, inner_block: fn _, _ -> "Você sai da partida." end}
          ],
          inner_block: [%{__slot__: :inner_block, inner_block: fn _, _ -> "Conteúdo" end}],
          actions: [%{__slot__: :actions, inner_block: fn _, _ -> "Confirmar" end}]
        })

      m_doc = LazyHTML.from_fragment(modal_html)

      assert LazyHTML.attribute(LazyHTML.query(m_doc, "[role=alertdialog]"), "aria-modal") == [
               "true"
             ]

      assert LazyHTML.text(m_doc) =~ "Desistir?"

      for tone <- ~w(hero light) do
        sheet_html =
          render_component(&bottom_sheet/1, %{
            id: "s-#{tone}",
            tone: tone,
            title: [%{__slot__: :title, inner_block: fn _, _ -> "Cura!" end}],
            inner_block: [%{__slot__: :inner_block, inner_block: fn _, _ -> "Nova corda" end}]
          })

        s_doc = LazyHTML.from_fragment(sheet_html)

        assert LazyHTML.attribute(LazyHTML.query(s_doc, "[role=dialog]"), "aria-modal") == [
                 "true"
               ]

        container_class =
          hd(LazyHTML.attribute(LazyHTML.query(s_doc, "#s-#{tone}-container"), "class"))

        assert container_class =~ "max-h-full"
        assert container_class =~ "overflow-y-auto"
        assert Enum.count(LazyHTML.query(s_doc, ".sticky.top-0")) == 1
        assert LazyHTML.text(s_doc) =~ "Cura!"
      end
    end

    test "alert, status_toast, flash, empty_state, table, list, back render cleanly" do
      for tone <- ~w(info success warning danger) do
        a_html =
          render_component(&alert/1, %{
            tone: tone,
            title: "Aviso",
            inner_block: [%{__slot__: :inner_block, inner_block: fn _, _ -> "Mensagem" end}]
          })

        assert LazyHTML.text(LazyHTML.from_fragment(a_html)) =~ "Mensagem"
      end

      toast_html =
        render_component(&status_toast/1, %{
          id: "t1",
          tone: "hero",
          inner_block: [%{__slot__: :inner_block, inner_block: fn _, _ -> "Link copiado" end}]
        })

      t_doc = LazyHTML.from_fragment(toast_html)
      assert LazyHTML.attribute(LazyHTML.query(t_doc, "[role=status]"), "aria-live") == ["polite"]

      flash_html =
        render_component(&flash/1, %{
          kind: :info,
          title: "Sucesso",
          inner_block: [%{__slot__: :inner_block, inner_block: fn _, _ -> "Salvo!" end}]
        })

      assert LazyHTML.text(LazyHTML.from_fragment(flash_html)) =~ "Salvo!"

      empty_html =
        render_component(&empty_state/1, %{
          icon: "hero-sparkles",
          title: "Nenhuma sala aberta",
          inner_block: [%{__slot__: :inner_block, inner_block: fn _, _ -> "Crie uma sala." end}]
        })

      assert LazyHTML.text(LazyHTML.from_fragment(empty_html)) =~ "Nenhuma sala aberta"

      table_html =
        render_component(&table/1, %{
          id: "players-table",
          rows: [%{id: 1, name: "Lia"}],
          col: [%{__slot__: :col, label: "Nome", inner_block: fn _, r -> r.name end}]
        })

      assert LazyHTML.text(LazyHTML.from_fragment(table_html)) =~ "Lia"

      list_html =
        render_component(&list/1, %{
          item: [%{__slot__: :item, title: "Idioma", inner_block: fn _, _ -> "PT-BR" end}]
        })

      assert LazyHTML.text(LazyHTML.from_fragment(list_html)) =~ "PT-BR"

      back_html =
        render_component(&back/1, %{
          navigate: "/",
          inner_block: [%{__slot__: :inner_block, inner_block: fn _, _ -> "Voltar" end}]
        })

      assert LazyHTML.attribute(LazyHTML.query(LazyHTML.from_fragment(back_html), "a"), "href") ==
               ["/"]
    end
  end
end
