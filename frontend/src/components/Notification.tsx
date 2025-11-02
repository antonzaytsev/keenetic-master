import React, { useState, useEffect, useRef } from 'react';
import './Notification.css';

export interface NotificationData {
  id: string;
  type: 'success' | 'error' | 'info' | 'warning';
  message: string;
  duration?: number;
}

interface NotificationProps {
  notification: NotificationData;
  onRemove: (id: string) => void;
}

const Notification: React.FC<NotificationProps> = ({ notification, onRemove }) => {
  const [isExiting, setIsExiting] = useState(false);
  const timeoutRef = useRef<NodeJS.Timeout | null>(null);

  useEffect(() => {
    const duration = notification.duration || 10000;
    
    timeoutRef.current = setTimeout(() => {
      setIsExiting(true);
      setTimeout(() => {
        onRemove(notification.id);
      }, 300);
    }, duration);

    return () => {
      if (timeoutRef.current) {
        clearTimeout(timeoutRef.current);
      }
    };
  }, [notification.id, notification.duration, onRemove]);

  const handleClose = () => {
    setIsExiting(true);
    setTimeout(() => {
      onRemove(notification.id);
    }, 300);
  };

  const getIcon = () => {
    switch (notification.type) {
      case 'success':
        return 'fa-check-circle';
      case 'error':
        return 'fa-exclamation-circle';
      case 'warning':
        return 'fa-exclamation-triangle';
      case 'info':
        return 'fa-info-circle';
      default:
        return 'fa-info-circle';
    }
  };

  return (
    <div className={`notification ${notification.type} ${isExiting ? 'exiting' : ''}`}>
      <div className="notification-content">
        <div className="notification-icon">
          <i className={`fas ${getIcon()}`}></i>
        </div>
        <div className="notification-message">
          {notification.message}
        </div>
        <button className="notification-close" onClick={handleClose}>
          <i className="fas fa-times"></i>
        </button>
      </div>
    </div>
  );
};

export default Notification;

