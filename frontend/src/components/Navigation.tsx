import React, { useState, useEffect } from 'react';
import { Navbar, Nav } from 'react-bootstrap';
import { LinkContainer } from 'react-router-bootstrap';
import { useLocation } from 'react-router-dom';
import { apiService } from '../services/api';

const Navigation: React.FC = () => {
  const location = useLocation();
  const [isConnected, setIsConnected] = useState(true);
  const [lastUpdated, setLastUpdated] = useState<Date>(new Date());

  useEffect(() => {
    const checkHealth = async () => {
      try {
        await apiService.getHealth();
        setIsConnected(true);
        setLastUpdated(new Date());
      } catch (error) {
        setIsConnected(false);
      }
    };

    checkHealth();
    const interval = setInterval(checkHealth, 30000);

    return () => clearInterval(interval);
  }, []);

  const formatTime = (date: Date) => {
    return date.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
  };

  const handleRefresh = () => {
    window.location.reload();
  };

  return (
    <Navbar expand="lg" className="navbar">
      <div className="header-container">
        <LinkContainer to="/">
          <Navbar.Brand>
            KeeneticMaster
          </Navbar.Brand>
        </LinkContainer>
        
        <Navbar.Toggle aria-controls="basic-navbar-nav" />
        <Navbar.Collapse id="basic-navbar-nav">
          <Nav className="me-auto">
            <LinkContainer to="/">
              <Nav.Link className={location.pathname === '/' ? 'active' : ''}>
                Domain Groups
              </Nav.Link>
            </LinkContainer>
            
            <LinkContainer to="/router-routes">
              <Nav.Link className={location.pathname === '/router-routes' ? 'active' : ''}>
                Router Routes
              </Nav.Link>
            </LinkContainer>
            
            <LinkContainer to="/dns-logs">
              <Nav.Link className={location.pathname === '/dns-logs' ? 'active' : ''}>
                DNS Logs
              </Nav.Link>
            </LinkContainer>
            
            <LinkContainer to="/dump-import">
              <Nav.Link className={location.pathname === '/dump-import' ? 'active' : ''}>
                Dump & Import
              </Nav.Link>
            </LinkContainer>
            
            <LinkContainer to="/settings">
              <Nav.Link className={location.pathname === '/settings' ? 'active' : ''}>
                Settings
              </Nav.Link>
            </LinkContainer>
          </Nav>
          
          <Nav className="ms-auto">
            <div className="d-flex align-items-center" style={{ gap: '0.75rem' }}>
              <div className={`connection-status ${!isConnected ? 'disconnected' : ''}`}>
                <span className="status-indicator"></span>
                <span>{isConnected ? 'Connected' : 'Disconnected'}</span>
              </div>
              <span className="text-muted" style={{ fontSize: '0.8125rem' }}>
                Updated {formatTime(lastUpdated)}
              </span>
              <button
                className="btn btn-refresh"
                onClick={handleRefresh}
                title="Refresh"
                style={{ padding: '0.375rem 0.625rem' }}
              >
                <i className="fas fa-sync-alt"></i>
              </button>
            </div>
          </Nav>
        </Navbar.Collapse>
      </div>
    </Navbar>
  );
};

export default Navigation;
