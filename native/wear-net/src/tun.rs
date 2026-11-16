use crate::meter::BandwidthMeter;
use parking_lot::Mutex;
use pcap_file::pcap::{PcapPacket, PcapWriter};
use std::{
    fs::File,
    io::{Error, ErrorKind, Result},
    pin::Pin,
    sync::Arc,
    task::{Context, Poll},
    time::{SystemTime, UNIX_EPOCH},
};
use tokio::io::{AsyncRead, AsyncWrite, ReadBuf};
use tokio::sync::mpsc;
use tokio_util::sync::PollSender;

pub struct MiWearTunDevice {
    pub inbound: mpsc::Receiver<Vec<u8>>,
    pub outbound: PollSender<Vec<u8>>,
    pub capture: Option<Arc<Mutex<PcapWriter<File>>>>,
    pub meter: BandwidthMeter,
}

impl AsyncRead for MiWearTunDevice {
    fn poll_read(
        mut self: Pin<&mut Self>,
        cx: &mut Context<'_>,
        buf: &mut ReadBuf<'_>,
    ) -> Poll<Result<()>> {
        match self.inbound.poll_recv(cx) {
            Poll::Ready(Some(packet)) => {
                let length = packet.len().min(buf.remaining());
                buf.put_slice(&packet[..length]);
                self.meter.add_read(length);
                capture(&mut self.capture, false, &packet);
                Poll::Ready(Ok(()))
            }
            Poll::Ready(None) => Poll::Ready(Err(Error::new(
                ErrorKind::BrokenPipe,
                "network ingress closed",
            ))),
            Poll::Pending => Poll::Pending,
        }
    }
}

impl AsyncWrite for MiWearTunDevice {
    fn poll_write(
        mut self: Pin<&mut Self>,
        cx: &mut Context<'_>,
        buf: &[u8],
    ) -> Poll<Result<usize>> {
        match self.outbound.poll_reserve(cx) {
            Poll::Ready(Ok(())) => match self.outbound.send_item(buf.to_vec()) {
                Ok(()) => {
                    self.meter.add_write(buf.len());
                    capture(&mut self.capture, true, buf);
                    Poll::Ready(Ok(buf.len()))
                }
                Err(_) => Poll::Ready(Err(Error::new(
                    ErrorKind::BrokenPipe,
                    "network egress closed",
                ))),
            },
            Poll::Ready(Err(_)) => Poll::Ready(Err(Error::new(
                ErrorKind::BrokenPipe,
                "network egress closed",
            ))),
            Poll::Pending => Poll::Pending,
        }
    }

    fn poll_flush(self: Pin<&mut Self>, _: &mut Context<'_>) -> Poll<Result<()>> {
        Poll::Ready(Ok(()))
    }
    fn poll_shutdown(self: Pin<&mut Self>, _: &mut Context<'_>) -> Poll<Result<()>> {
        Poll::Ready(Ok(()))
    }
}

fn capture(writer: &mut Option<Arc<Mutex<PcapWriter<File>>>>, outbound: bool, packet: &[u8]) {
    let Some(writer) = writer else { return };
    let mut ethernet = if outbound {
        hex("a5a5a5a5a5a50000000000000800")
    } else {
        hex("000000000000a5a5a5a5a5a50800")
    };
    ethernet.extend_from_slice(packet);
    let _ = writer.lock().write_packet(&PcapPacket {
        timestamp: SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default(),
        orig_len: ethernet.len() as u32,
        data: ethernet.into(),
    });
}

fn hex(value: &str) -> Vec<u8> {
    value
        .as_bytes()
        .as_chunks::<2>()
        .0
        .iter()
        .map(|pair| u8::from_str_radix(std::str::from_utf8(pair).expect("hex"), 16).expect("hex"))
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::task::Waker;
    use std::time::Duration;

    #[test]
    fn pending_writes_do_not_duplicate_metering_or_capture() {
        let path = std::env::temp_dir().join(format!(
            "wear-net-backpressure-{}-{}.pcap",
            std::process::id(),
            SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap()
                .as_nanos(),
        ));
        let capture = Arc::new(Mutex::new(
            PcapWriter::new(File::create(&path).unwrap()).unwrap(),
        ));
        let (sender, mut receiver) = mpsc::channel(1);
        sender.try_send(vec![0]).unwrap();
        let (_, inbound) = mpsc::channel(1);
        let meter = BandwidthMeter::new(Duration::from_secs(10));
        let mut tun = MiWearTunDevice {
            inbound,
            outbound: PollSender::new(sender),
            capture: Some(capture.clone()),
            meter: meter.clone(),
        };
        let initial_size = std::fs::metadata(&path).unwrap().len();
        let mut context = Context::from_waker(Waker::noop());
        let bytes = [1, 2, 3];
        for _ in 0..3 {
            assert!(
                Pin::new(&mut tun)
                    .poll_write(&mut context, &bytes)
                    .is_pending()
            );
        }
        assert_eq!(meter.write_speed(), 0.0);
        assert_eq!(std::fs::metadata(&path).unwrap().len(), initial_size);
        receiver.try_recv().unwrap();
        assert!(matches!(
            Pin::new(&mut tun).poll_write(&mut context, &bytes),
            Poll::Ready(Ok(3))
        ));
        assert_eq!(receiver.try_recv().unwrap(), bytes);
        assert!(meter.write_speed() > 0.0);
        // One PCAP packet header and one Ethernet frame.
        assert_eq!(
            std::fs::metadata(&path).unwrap().len(),
            initial_size + 16 + 14 + 3
        );
        drop(tun);
        drop(capture);
        std::fs::remove_file(path).unwrap();
    }
}
