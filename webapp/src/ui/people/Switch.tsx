// An on/off switch with its label and one line saying what it does.
import './people.css';

export function Switch({ label, detail, checked, disabled, onChange }: {
  label: string; detail?: string; checked: boolean; disabled?: boolean; onChange: (next: boolean) => void;
}) {
  return (
    <label className="switch-row">
      <span className="grow">
        <span className="switch-label">{label}</span>
        {detail ? <span className="small muted switch-detail">{detail}</span> : null}
      </span>
      <input type="checkbox" role="switch" className="switch" checked={checked} disabled={disabled}
        onChange={(event) => onChange(event.target.checked)} />
    </label>
  );
}
