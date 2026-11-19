---
name: frontend-modal-standard
description: Binding rules for a modal form across the frontends: shell, title, button placement, loading/disabled states, submit/cancel behavior, width. Use when you create or modify a modal that carries a form, after rule 17 of .agents/rules/frontend.md has established that this screen may be a modal at all (a decision about a row on screen, a one-field change, a picker, a short sectionless form). Creating or editing an entity is a page, not a modal, and this skill does not cover it.
---

Binding rules for a modal form. Ensures visual consistency, UX safety, and accessibility across
every modal that carries one.

## First: is this allowed to be a modal?

`.agents/rules/frontend.md` rule 17 decides, and it is binding: **creating or editing a record the
backend stores as a row of its own is a page at its own address, never a modal.** A modal is for a
decision about a row already on screen (pause, cancel, approve), a single-field change, a picker
over things that already exist, or a short form with no sections that nobody would leave half
done.

If the screen you are building is an entity form, stop here and read rule 17 instead. The rest of
this skill is for the modals that survive that test. The existing `*FormModal` components that do
not are debt from before the rule, not a pattern to copy.

## When to use

Any time you create or modify a modal with a form that rule 17 allows to be one.

## Modal shell

```tsx
<Modal
  title="Pause location"        // Verb + noun, sentence case
  open={open}
  onCancel={onClose}
  footer={null}                 // Custom footer inside form, never antd's default OK/Cancel
  destroyOnClose                // Reset form state on close (or destroyOnHidden)
  width={520}                   // Standard width. 520 for simple forms, 720 for wide content
>
```

- **Title**: verb + noun, sentence case ("Add member", "Pause location"). Never "New thing" or "THING CREATION".
- **Width**: 520px for most forms (3-6 fields). 720px only when the form genuinely needs it (side-by-side columns, wide editors).
- **Footer**: always `footer={null}` — buttons live inside the form, not in antd's modal footer.

## Form inside modal

Use antd `<Form>` with `layout="vertical"`. Never raw `<form>` + `<label>` + `<Controller>` — that pattern misses required-field asterisks, validation styling, and consistent spacing.

```tsx
<Form form={form} layout="vertical" onFinish={handleSubmit}>
  <Form.Item label="Name" name="name" rules={[{ required: true, message: "Name is required" }]}>
    <Input placeholder="Enter name" />
  </Form.Item>

  {/* ... more fields ... */}

  <div className="flex justify-end gap-2 pt-2">
    <Button onClick={onClose} disabled={isSubmitting}>
      Cancel
    </Button>
    <Button type="primary" htmlType="submit" loading={isSubmitting}>
      Create
    </Button>
  </div>
</Form>
```

## Field rules

- **Required fields**: use `rules={[{ required: true, message: "X is required" }]}` — antd renders the red asterisk automatically.
- **Validation**: regex, min/max length, custom validators go in `rules` array, not manual `if` checks.
- **Placeholders**: every input has a placeholder. Use "Enter name", "Select country", "Describe what this is for".
- **Help text**: use `<p className="text-xs text-gray-400 mt-1">` below the Form.Item when the field needs explanation. Not a tooltip — inline text.

## Buttons

- **Position**: bottom-right of the form, `flex justify-end gap-2 pt-2`.
- **Order**: Cancel (left), Primary action (right). Never reversed.
- **Cancel**: `<Button onClick={onClose} disabled={isSubmitting}>Cancel</Button>` — disabled during submit to prevent close mid-flight.
- **Submit**: `<Button type="primary" htmlType="submit" loading={isSubmitting}>Verb</Button>` — `loading` locks the button and shows spinner. `htmlType="submit"` triggers form validation.
- **No `block`**: buttons are never full-width in modals. No `block` prop.
- **Label**: single verb matching the modal title: "Pause", "Save", "Add". Not "Submit", not "OK", not "Pause Location" (the modal title already says what).

## Submit handler

```tsx
const [isSubmitting, setIsSubmitting] = useState(false);

const handleSubmit = async (values: FormValues) => {
  setIsSubmitting(true);
  try {
    await backend.service.create(values);
    toast.success("Thing created");
    onClose();
    await onSuccess();
  } catch (err) {
    toast.error(err instanceof Error ? err.message : "Failed to create");
  } finally {
    setIsSubmitting(false);
  }
};
```

- `isSubmitting` gates both buttons (Cancel disabled, Submit loading).
- Success: toast + close + refresh. In that order.
- Error: toast only. Modal stays open so the user can fix and retry.
- `finally` always clears `isSubmitting`.

## Select fields

- Use antd `<Select>` inside `<Form.Item>`, not a raw `<select>`.
- Multi-select: `mode="multiple"` with `optionFilterProp="label"` and `showSearch`.
- Country/market selects: fetch from `marketplace_configuration.supportedMarketsList`.

## What NOT to do

- **Never** use react-hook-form (`useForm`, `Controller`) in modal forms. Use antd `Form.useForm()`.
- **Never** use raw `<form>` + `<label>` — it misses required asterisks and validation UX.
- **Never** put buttons in `Modal`'s `footer` prop or `onOk`/`okText` — custom footer inside the form.
- **Never** use `block` on modal buttons.
- **Never** let both buttons be clickable during submit.
- **Never** close the modal on error.

## Checklist

Before finishing a modal form, verify:
- [ ] Rule 17 allows this screen to be a modal at all (it is not an entity form)
- [ ] `footer={null}` on Modal
- [ ] `width={520}` (or 720 if justified)
- [ ] antd `<Form layout="vertical">`, not raw form
- [ ] Required fields have `rules` with `required: true`
- [ ] Buttons: `justify-end`, Cancel left, Primary right, no `block`
- [ ] Submit button has `loading={isSubmitting}` and `htmlType="submit"`
- [ ] Cancel button has `disabled={isSubmitting}`
- [ ] `isSubmitting` state with try/catch/finally
- [ ] Success: toast + close + refresh
- [ ] Error: toast only, modal stays open
