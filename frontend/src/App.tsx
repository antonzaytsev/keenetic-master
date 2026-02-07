import React from 'react';
import { BrowserRouter as Router, Routes, Route } from 'react-router-dom';
import 'bootstrap/dist/css/bootstrap.min.css';
import 'bootstrap/dist/js/bootstrap.bundle.min.js';

import { NotificationProvider } from './contexts/NotificationContext';
import Navigation from './components/Navigation';
import DomainGroups from './components/DomainGroups';
import GroupDetails from './components/GroupDetails';
import AddGroup from './components/AddGroup';
import RouterRoutes from './components/RouterRoutes';
import DnsLogs from './components/DnsLogs';
import DumpImport from './components/DumpImport';
import Settings from './components/Settings';

import './App.css';

function App() {
  return (
    <NotificationProvider>
      <Router>
        <div className="App">
          <Navigation />
          <div className="content-container">
            <Routes>
              <Route path="/" element={<DomainGroups />} />
              <Route path="/groups/add" element={<AddGroup />} />
              <Route path="/groups/:groupName" element={<GroupDetails />} />
              <Route path="/router-routes" element={<RouterRoutes />} />
              <Route path="/dns-logs" element={<DnsLogs />} />
              <Route path="/dump-import" element={<DumpImport />} />
              <Route path="/settings" element={<Settings />} />
            </Routes>
          </div>
        </div>
      </Router>
    </NotificationProvider>
  );
}

export default App;