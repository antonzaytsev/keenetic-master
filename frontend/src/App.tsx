import React from 'react';
import { BrowserRouter as Router, Routes, Route } from 'react-router-dom';
import 'bootstrap/dist/css/bootstrap.min.css';
import 'bootstrap/dist/js/bootstrap.bundle.min.js';

import Navigation from './components/Navigation';
import DomainGroups from './components/DomainGroups';
import GroupDetails from './components/GroupDetails';
import IPAddresses from './components/IPAddresses';
import SyncStatus from './components/SyncStatus';

import './App.css';

function App() {
  return (
    <Router>
      <div className="App">
        <Navigation />
        <div className="container mt-4">
          <Routes>
            <Route path="/" element={<DomainGroups />} />
            <Route path="/groups/:groupName" element={<GroupDetails />} />
            <Route path="/ip-addresses" element={<IPAddresses />} />
            <Route path="/sync-status" element={<SyncStatus />} />
          </Routes>
        </div>
      </div>
    </Router>
  );
}

export default App;