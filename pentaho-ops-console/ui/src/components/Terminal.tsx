import { useEffect, useRef, useState } from 'react';
import { streamJob, cancelJob } from '../api';
import CancelJobDialog from './CancelJobDialog';

interface Props {
  jobId: string | null;
  onClose?: () => void;
  onDone?: () => void;
  embedded?: boolean;
}

interface Line {
  stream: string;
  text: string;
}

export default function Terminal({ jobId, onClose, onDone, embedded = false }: Props) {
  const [lines, setLines] = useState<Line[]>([]);
  const [done, setDone] = useState(false);
  const [expanded, setExpanded] = useState(false);
  const [showCancelConfirm, setShowCancelConfirm] = useState(false);
  const [canceling, setCanceling] = useState(false);
  const [cancelError, setCancelError] = useState<string | null>(null);
  const bottomRef = useRef<HTMLDivElement>(null);
  const onDoneRef = useRef(onDone);
  onDoneRef.current = onDone;

  useEffect(() => {
    if (!jobId) return;
    setLines([]);
    setDone(false);
    setExpanded(false);
    setShowCancelConfirm(false);
    setCanceling(false);
    setCancelError(null);

    const close = streamJob(
      jobId,
      (line) => setLines((prev) => [...prev, line]),
      () => { setDone(true); onDoneRef.current?.(); },
    );
    return close;
  }, [jobId]);

  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: 'smooth' });
  }, [lines]);

  if (!jobId) return null;

  function downloadLog() {
    const text = lines.map((l) => l.text).join('\n');
    const blob = new Blob([text], { type: 'text/plain' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `process-${jobId}.log`;
    a.click();
    URL.revokeObjectURL(url);
  }

  async function confirmCancel() {
    if (!jobId) return;
    setCanceling(true);
    setCancelError(null);
    try {
      await cancelJob(jobId);
      setShowCancelConfirm(false);
    } catch (error) {
      setCancelError(error instanceof Error ? error.message : 'Could not cancel the process.');
    } finally {
      setCanceling(false);
    }
  }

  const wrapper: React.CSSProperties = expanded
    ? { position: 'fixed', inset: 0, zIndex: 1000, display: 'flex', flexDirection: 'column' }
    : {
      maxHeight: embedded ? '100%' : 400,
      height: embedded ? '100%' : undefined,
      display: 'flex',
      flexDirection: 'column',
      borderRadius: 6,
      overflow: 'hidden',
      marginTop: embedded ? 0 : 16,
      border: embedded ? '1px solid #d9e1ea' : undefined,
    };

  return (
    <div style={wrapper}>
      <div style={headerStyle}>
        <span style={{ fontWeight: 600 }}>Process: {jobId}</span>
        <span style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
          <button onClick={downloadLog} style={headerBtn} title="Download log">
            ↓
          </button>
          <button
            onClick={() => setExpanded(!expanded)}
            style={headerBtn}
            title={expanded ? 'Collapse' : 'Expand'}
          >
            {expanded ? '⊟' : '⊞'}
          </button>
          {!done && (
            <button
              onClick={() => setShowCancelConfirm(true)}
              style={{ ...headerBtn, background: '#c0392b' }}
              title="Review cancellation warning"
            >
              Cancel
            </button>
          )}
          {done && <span style={{ color: '#27ae60', fontSize: 12 }}>Done</span>}
          {onClose && (
            <button onClick={() => { setExpanded(false); onClose(); }} style={headerBtn} title="Close terminal output">
              Close
            </button>
          )}
        </span>
      </div>
      <pre style={outputStyle}>
        {lines.map((l, i) => (
          <div key={i} style={{ color: l.stream === 'stderr' ? '#e74c3c' : '#ecf0f1' }}>
            {l.text}
          </div>
        ))}
        <div ref={bottomRef} />
      </pre>
      <CancelJobDialog
        open={showCancelConfirm && !done}
        jobId={jobId}
        canceling={canceling}
        error={cancelError}
        onDismiss={() => {
          setShowCancelConfirm(false);
          setCancelError(null);
        }}
        onConfirm={confirmCancel}
      />
    </div>
  );
}

const headerStyle: React.CSSProperties = {
  background: '#2d2d2d',
  padding: '8px 12px',
  display: 'flex',
  justifyContent: 'space-between',
  alignItems: 'center',
  color: '#ecf0f1',
  fontSize: 13,
  flexShrink: 0,
};

const headerBtn: React.CSSProperties = {
  background: '#555',
  color: '#fff',
  border: 'none',
  padding: '4px 10px',
  borderRadius: 4,
  cursor: 'pointer',
  fontSize: 12,
};

const outputStyle: React.CSSProperties = {
  flex: 1,
  overflow: 'auto',
  padding: 12,
  margin: 0,
  fontSize: 13,
  lineHeight: 1.5,
  fontFamily: 'Menlo, Monaco, "Courier New", monospace',
  color: '#ecf0f1',
  background: '#1e1e1e',
};
