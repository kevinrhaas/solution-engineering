import { useEffect, useState } from 'react';

interface Props {
  open: boolean;
  jobId: string | null;
  canceling?: boolean;
  error?: string | null;
  onDismiss: () => void;
  onConfirm: () => void | Promise<void>;
}

export default function CancelJobDialog({
  open,
  jobId,
  canceling = false,
  error,
  onDismiss,
  onConfirm,
}: Props) {
  const [acknowledged, setAcknowledged] = useState(false);

  useEffect(() => {
    if (open) setAcknowledged(false);
  }, [open, jobId]);

  if (!open || !jobId) return null;

  return (
    <div style={backdropStyle} role="presentation">
      <form
        role="dialog"
        aria-modal="true"
        aria-labelledby="cancel-process-title"
        style={dialogStyle}
        onSubmit={(event) => {
          event.preventDefault();
          if (acknowledged && !canceling) void onConfirm();
        }}
      >
        <h3 id="cancel-process-title" style={titleStyle}>Cancel Running Process?</h3>
        <p style={bodyStyle}>
          Process <code style={codeStyle}>{jobId}</code> will be canceled now. It cannot be automatically restarted,
          and a new process will need to be created if you want to run this work again.
        </p>

        <label style={checkRowStyle}>
          <input
            type="checkbox"
            checked={acknowledged}
            onChange={(event) => setAcknowledged(event.target.checked)}
            disabled={canceling}
          />
          <span>I understand this process cannot be automatically restarted.</span>
        </label>

        {error && <div style={errorStyle}>{error}</div>}

        <div style={actionsStyle}>
          <button type="button" onClick={onDismiss} style={secondaryButtonStyle} disabled={canceling}>
            Keep Running
          </button>
          <button
            type="submit"
            style={{
              ...dangerButtonStyle,
              opacity: acknowledged && !canceling ? 1 : 0.55,
              cursor: acknowledged && !canceling ? 'pointer' : 'not-allowed',
            }}
            disabled={!acknowledged || canceling}
          >
            {canceling ? 'Canceling...' : 'Cancel Process'}
          </button>
        </div>
      </form>
    </div>
  );
}

const backdropStyle: React.CSSProperties = {
  position: 'fixed',
  inset: 0,
  zIndex: 2000,
  background: 'rgba(15, 23, 42, 0.45)',
  display: 'flex',
  alignItems: 'center',
  justifyContent: 'center',
  padding: 20,
};

const dialogStyle: React.CSSProperties = {
  width: 'min(440px, 100%)',
  background: '#fff',
  color: '#1f2d3d',
  borderRadius: 6,
  boxShadow: '0 20px 45px rgba(15, 23, 42, 0.28)',
  padding: 20,
};

const titleStyle: React.CSSProperties = {
  margin: '0 0 10px',
  fontSize: 18,
};

const bodyStyle: React.CSSProperties = {
  margin: '0 0 16px',
  color: '#4b5b6b',
  lineHeight: 1.45,
  fontSize: 14,
};

const codeStyle: React.CSSProperties = {
  background: '#f1f4f8',
  borderRadius: 4,
  padding: '1px 5px',
};

const checkRowStyle: React.CSSProperties = {
  display: 'flex',
  gap: 8,
  alignItems: 'flex-start',
  color: '#1f2d3d',
  fontSize: 14,
  lineHeight: 1.35,
  marginBottom: 16,
};

const errorStyle: React.CSSProperties = {
  background: '#fdecea',
  color: '#a93226',
  border: '1px solid #f5c6cb',
  borderRadius: 4,
  padding: '8px 10px',
  fontSize: 13,
  marginBottom: 16,
};

const actionsStyle: React.CSSProperties = {
  display: 'flex',
  justifyContent: 'flex-end',
  gap: 10,
  flexWrap: 'wrap',
};

const secondaryButtonStyle: React.CSSProperties = {
  background: '#eef2f6',
  color: '#1f2d3d',
  border: 'none',
  borderRadius: 4,
  padding: '8px 14px',
  cursor: 'pointer',
  fontSize: 13,
};

const dangerButtonStyle: React.CSSProperties = {
  background: '#c0392b',
  color: '#fff',
  border: 'none',
  borderRadius: 4,
  padding: '8px 14px',
  fontSize: 13,
};
