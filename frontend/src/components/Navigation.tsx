import React from 'react';
import { Navbar, Nav, Container } from 'react-bootstrap';
import { LinkContainer } from 'react-router-bootstrap';
import { useLocation } from 'react-router-dom';

const Navigation: React.FC = () => {
  const location = useLocation();

  return (
    <Navbar expand="lg" className="navbar-dark">
      <Container>
        <LinkContainer to="/">
          <Navbar.Brand>
            <i className="fas fa-network-wired me-2"></i>
            KeeneticMaster
          </Navbar.Brand>
        </LinkContainer>
        
        <Navbar.Toggle aria-controls="basic-navbar-nav" />
        <Navbar.Collapse id="basic-navbar-nav">
          <Nav className="ms-auto">
            <LinkContainer to="/">
              <Nav.Link className={location.pathname === '/' ? 'active' : ''}>
                <i className="fas fa-layer-group me-1"></i>
                Domain Groups
              </Nav.Link>
            </LinkContainer>
            
            <LinkContainer to="/ip-addresses">
              <Nav.Link className={location.pathname === '/ip-addresses' ? 'active' : ''}>
                <i className="fas fa-network-wired me-1"></i>
                IP Addresses
              </Nav.Link>
            </LinkContainer>
            
            <LinkContainer to="/router-routes">
              <Nav.Link className={location.pathname === '/router-routes' ? 'active' : ''}>
                <i className="fas fa-router me-1"></i>
                Router Routes
              </Nav.Link>
            </LinkContainer>
            
            <LinkContainer to="/sync-status">
              <Nav.Link className={location.pathname === '/sync-status' ? 'active' : ''}>
                <i className="fas fa-sync me-1"></i>
                Sync Status
              </Nav.Link>
            </LinkContainer>
          </Nav>
        </Navbar.Collapse>
      </Container>
    </Navbar>
  );
};

export default Navigation;
