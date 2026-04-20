function EEG_out = reviewwindow(EEG)
% REVIEWWINDOW  Interactive EEG / ICA-activation review window (EEGLAB)
%
% Usage
%   EEG_out = reviewwindow(EEG)
%
% Returns
%   EEG_out : updated EEG struct after REJECT is pressed, or [] if the
%             window is closed without rejecting.
%
% Mouse
%   Click channel label        : toggle bad (turns red)
%   Click in signal area       : set first-click time marker
%   Shift-Click in signal area : mark period [marker … click] as bad (orange overlay)
%
% Keyboard
%   ← / → arrow keys : scroll one window
%   ↑ / ↓ arrow keys : decrease / increase scale
%
% Buttons
%   ◀ Prev / Next ▶   : scroll through time
%   Scale − / Scale + : adjust scale ±10 µV per step
%   Show ICA / Show EEG : toggle between EEG.data and EEG.icaact
%                         (ICA mode also shows topoplot of each IC on the right)
%   REJECT            : apply all marked rejections, write updated EEG to workspace
% -------------------------------------------------------------------------

if nargin < 1
    error('reviewwindow: EEG struct required.');
end

EEG_out = [];   % returned as [] unless REJECT is pressed

%% ---------- initial state -----------------------------------------------
n_chans = size(EEG.data, 1);
has_ica = isfield(EEG, 'icaact') && ~isempty(EEG.icaact);

s.EEG         = EEG;
s.win_start   = 0;       % window start [s]
s.win_dur     = 12;      % window width [s]
s.scale_eeg   = 50;      % half-height per EEG channel [µV]
s.scale_ica   = 20;      % half-height per IC activation [µV]
s.mode        = 'eeg';   % 'eeg' | 'ica'
s.bad_chans   = false(1, n_chans);
s.bad_ics     = false(1, 0);
if has_ica
    s.bad_ics = false(1, size(EEG.icaact, 1));
end
s.bad_periods = zeros(0, 2);   % [start_samp, end_samp] rows
s.click_time  = NaN;           % pending first-click [s]
s.topo_axes   = gobjects(1, 0);  % topoplot axes handles (ICA mode)
s.psd_axes    = gobjects(1, 0);  % PSD axes handles (ICA mode)
s.topo_N      = 0;               % N when topo axes were last built
s.out_EEG     = [];              % set by reject_cb; read after uiwait

%% ---------- figure -------------------------------------------------------
scr = get(0, 'ScreenSize');
fw  = round(scr(3) * 0.88);
fh  = round(scr(4) * 0.88);
fx  = round((scr(3) - fw) / 2);
fy  = round((scr(4) - fh) / 2);

hfig = figure( ...
    'Position',    [fx fy fw fh], ...
    'Name',        'EEG Review Window', ...
    'NumberTitle', 'off', ...
    'Color',       [1 1 1], ...
    'Resize',          'on', ...
    'CloseRequestFcn', @close_req_cb, ...
    'KeyPressFcn',     @key_cb);

%% ---------- layout constants (normalised) --------------------------------
CHAN_W  = 0.085;   % left channel-label strip
TOPO_W  = 0.11;    % topoplot column width (ICA mode)
PSD_W   = 0.14;    % PSD column width (ICA mode)
BTN_H   = 0.072;   % bottom button bar
M       = 0.008;   % general margin

ax_l = CHAN_W + M;
ax_b = BTN_H  + M;
ax_w = 1 - ax_l - M;           % full signal-area width (EEG mode)
ax_h = 1 - ax_b - M * 2;

%% ---------- signal axes --------------------------------------------------
hax = axes('Parent', hfig, ...
    'Units',    'normalized', ...
    'Position', [ax_l ax_b ax_w ax_h], ...
    'Color',    [1.00 1.00 0.93], ...
    'XColor',   [0.2 0.2 0.2], ...
    'YColor',   'none', ...
    'YTick',    [], ...
    'Box',      'off', ...
    'FontSize', 9, ...
    'XGrid',    'on', ...
    'GridColor', [0.82 0.82 0.72], ...
    'GridAlpha', 0.9, ...
    'ButtonDownFcn', @ax_click_cb);
xlabel(hax, 'Time (s)', 'Color', [0.2 0.2 0.2]);
hold(hax, 'on');

%% ---------- channel-label axes (left strip) ------------------------------
hax_ch = axes('Parent', hfig, ...
    'Units',    'normalized', ...
    'Position', [M ax_b CHAN_W-M*2 ax_h], ...
    'Color',    [1.00 1.00 0.93], ...
    'XColor',   'none', ...
    'YColor',   'none', ...
    'YTick',    [], ...
    'XTick',    [], ...
    'Box',      'off', ...
    'HitTest',  'on');
hold(hax_ch, 'on');

%% ---------- bottom buttons -----------------------------------------------
bw = 0.08; bh = 0.048; by = 0.012; gap = 0.006;
bx = ax_l;

uicontrol('Style','pushbutton','String','◀  Prev', ...
    'Units','normalized','Position',[bx by bw bh], ...
    'FontSize',9,'Callback',@(~,~)scroll_cb(-1));

bx = bx + bw + gap;
uicontrol('Style','pushbutton','String','Next  ▶', ...
    'Units','normalized','Position',[bx by bw bh], ...
    'FontSize',9,'Callback',@(~,~)scroll_cb(+1));

bx = bx + bw + gap*4;
uicontrol('Style','pushbutton','String','Scale  −', ...
    'Units','normalized','Position',[bx by bw bh], ...
    'FontSize',9,'Callback',@(~,~)scale_cb(-10));

bx = bx + bw + gap;
uicontrol('Style','pushbutton','String','Scale  +', ...
    'Units','normalized','Position',[bx by bw bh], ...
    'FontSize',9,'Callback',@(~,~)scale_cb(+10));

bx = bx + bw + gap;
hscale_lbl = uicontrol('Style','text','String','±50 µV', ...
    'Units','normalized','Position',[bx by+0.004 bw*0.85 bh*0.8], ...
    'BackgroundColor',[1 1 1],'ForegroundColor',[0.1 0.1 0.1], ...
    'FontSize',9,'FontWeight','bold','HorizontalAlignment','center');

bx = bx + bw + gap*4;
htoggle = uicontrol('Style','pushbutton','String','Show ICA', ...
    'Units','normalized','Position',[bx by bw bh], ...
    'FontSize',9,'Callback',@toggle_cb);
if ~has_ica, set(htoggle,'Enable','off','String','No ICA'); end

bx = bx + bw + gap*4;
uicontrol('Style','pushbutton','String','REJECT', ...
    'Units','normalized','Position',[bx by bw bh], ...
    'BackgroundColor',[0.72 0.13 0.13],'ForegroundColor','w', ...
    'FontWeight','bold','FontSize',10,'Callback',@reject_cb);

bx = bx + bw + gap;
uicontrol('Style','pushbutton','String','Cancel', ...
    'Units','normalized','Position',[bx by bw bh], ...
    'FontSize',10,'Callback',@close_req_cb);

bx = bx + bw + gap*4;
hrun_ica = uicontrol('Style','pushbutton','String','Run ICA', ...
    'Units','normalized','Position',[bx by bw bh], ...
    'BackgroundColor',[0.13 0.38 0.68],'ForegroundColor','w', ...
    'FontWeight','bold','FontSize',10,'Callback',@run_ica_cb);

%% ---------- store handles and draw ---------------------------------------
s.hfig       = hfig;
s.hax        = hax;
s.hax_ch     = hax_ch;
s.htoggle    = htoggle;
s.hscale_lbl = hscale_lbl;

setappdata(hfig, 's', s);
redraw();

%% --- block here until REJECT or window close ----------------------------
uiwait(hfig);

if ishandle(hfig)
    s       = getappdata(hfig, 's');
    EEG_out = s.out_EEG;   % [] if closed without REJECT, EEG if REJECT
    delete(hfig);
% else: figure was already destroyed (e.g. force-closed); EEG_out stays []
end

%% ==========================================================================
%  REDRAW
%% ==========================================================================
function redraw()
    s   = getappdata(hfig, 's');
    EEG = s.EEG;

    %% pick data & labels
    if strcmp(s.mode, 'ica')
        data    = double(EEG.icaact);
        N       = min(size(data, 1), 24);   % show top 24 ICs only
        labels  = arrayfun(@(k)sprintf('IC%d',k), 1:N, 'UniformOutput',false);
        bad_arr = s.bad_ics;
    else
        data = double(EEG.data);
        N    = size(data, 1);
        if isfield(EEG,'chanlocs') && numel(EEG.chanlocs) >= N
            labels = {EEG.chanlocs(1:N).labels};
        else
            labels = arrayfun(@(k)sprintf('Ch%d',k), 1:N, 'UniformOutput',false);
        end
        bad_arr = s.bad_chans;
    end

    if numel(bad_arr) < N
        bad_arr(end+1:N) = false;
    end

    %% clamp window
    max_t = size(data,2) / EEG.srate;
    s.win_start = max(0, min(s.win_start, max_t - s.win_dur));

    i1   = max(1, round(s.win_start * EEG.srate) + 1);
    i2   = min(size(data,2), i1 + round(s.win_dur * EEG.srate) - 1);
    tvec = (i1:i2) / EEG.srate;

    if strcmp(s.mode,'ica')
        sc = s.scale_ica;
    else
        sc = s.scale_eeg;
    end
    spacing = sc * 2.6;
    ybot    = -sc * 1.2;
    ytop    = (N-1)*spacing + sc * 1.5;

    %% ---- topo panel (ICA mode) ------------------------------------------
    has_winv     = isfield(EEG,'icawinv') && ~isempty(EEG.icawinv);
    has_chanlocs = isfield(EEG,'chanlocs') && ~isempty(EEG.chanlocs);

    if strcmp(s.mode,'ica') && has_winv
        sig_w  = ax_w - TOPO_W - PSD_W - M*2;
        topo_x = ax_l + sig_w + M;
        psd_x  = topo_x + TOPO_W + M;
    else
        sig_w  = ax_w;
        topo_x = 1 - M;   % off-screen, unused
        psd_x  = 1 - M;
    end

    % Resize signal axes to current mode width
    set(s.hax, 'Position', [ax_l ax_b sig_w ax_h]);

    %% ---- clear signal + label axes, draw traces -------------------------
    cla(s.hax);
    cla(s.hax_ch);
    hold(s.hax,    'on');
    hold(s.hax_ch, 'on');

    set(s.hax,    'YLim',[ybot ytop], 'XLim',[tvec(1) tvec(end)]);
    set(s.hax_ch, 'YLim',[ybot ytop], 'XLim',[0 1]);

    %% bad-period patches
    for bp = 1:size(s.bad_periods, 1)
        bs = s.bad_periods(bp,1) / EEG.srate;
        be = s.bad_periods(bp,2) / EEG.srate;
        xs = max(bs, tvec(1));
        xe = min(be, tvec(end));
        if xs < xe
            patch(s.hax, [xs xe xe xs], [ybot ybot ytop ytop], ...
                [1 0.55 0.08], ...
                'FaceAlpha', 0.20, 'EdgeColor',[1 0.5 0.1], ...
                'EdgeAlpha', 0.5,  'LineWidth', 0.8, ...
                'HitTest','off');
        end
    end

    %% pending-click marker
    if ~isnan(s.click_time) && s.click_time >= tvec(1) && s.click_time <= tvec(end)
        plot(s.hax, [s.click_time s.click_time], [ybot ytop], ...
            '--', 'Color',[0.75 0.35 0], 'LineWidth',1.5, 'HitTest','off');
        text(s.hax, s.click_time, ytop*0.985, ...
            sprintf('%.2fs', s.click_time), ...
            'Color',[0.6 0.25 0],'FontSize',7, ...
            'HorizontalAlignment','center','VerticalAlignment','top', ...
            'HitTest','off');
    end

    %% precompute IC-cleaned signal for EEG display (if any ICs marked bad)
    show_cleaned = strcmp(s.mode,'eeg') && any(s.bad_ics) && ...
                   isfield(EEG,'icawinv') && ~isempty(EEG.icawinv) && ...
                   isfield(EEG,'icaact')  && ~isempty(EEG.icaact);
    if show_cleaned
        bad_ic_idx   = find(s.bad_ics);
        cleaned_data = double(EEG.data);
        try
            cleaned_data(EEG.icachansind, :) = ...
                EEG.data(EEG.icachansind, :) - ...
                EEG.icawinv(:, bad_ic_idx) * EEG.icaact(bad_ic_idx, :);
        catch err
            fprintf('[reviewwindow] cleaned_data error: %s\n', err.message);
            show_cleaned = false;
        end
    end

    %% traces + channel labels
    col_good  = [0   0   0  ];   % black
    col_bad   = [0.85 0.10 0.10]; % red
    col_orig  = [0.45 0.65 0.88]; % light blue for original signal when ICs removed
    col_zero  = [0.86 0.86 0.86]; % subtle gridline per channel
    col_ch_bg = [1.00 1.00 0.93];

    for i = 1:N
        y0  = (N - i) * spacing;
        seg = data(i, i1:i2);
        seg = max(min(seg, 3*sc), -3*sc);

        c = col_good;
        if i <= numel(bad_arr) && bad_arr(i), c = col_bad; end

        % zero line
        plot(s.hax, [tvec(1) tvec(end)], [y0 y0], ...
            'Color', col_zero, 'LineWidth', 0.4, 'HitTest','off');

        % trace
        if show_cleaned
            % original signal in light grey behind
            plot(s.hax, tvec, seg + y0, ...
                'Color', col_orig, 'LineWidth', 0.5, 'HitTest','off');
            % IC-cleaned signal in foreground
            seg_cl = double(cleaned_data(i, i1:i2));
            seg_cl = max(min(seg_cl, 3*sc), -3*sc);
            plot(s.hax, tvec, seg_cl + y0, ...
                'Color', c, 'LineWidth', 0.6, 'HitTest','off');
        else
            plot(s.hax, tvec, seg + y0, ...
                'Color', c, 'LineWidth', 0.5, 'HitTest','off');
        end

        % channel label (clickable text in left strip)
        text(s.hax_ch, 0.96, y0, labels{i}, ...
            'HorizontalAlignment','right', ...
            'VerticalAlignment',  'middle', ...
            'FontSize',  8, ...
            'FontWeight','bold', ...
            'Color',     c, ...
            'BackgroundColor', col_ch_bg, ...
            'Margin',    1, ...
            'Clipping',  'on', ...
            'Interpreter','none', ...
            'ButtonDownFcn', {@chan_click_cb, i});
    end

    %% amplitude scale bar (top-right of signal axes)
    tx = tvec(end) - (tvec(end)-tvec(1))*0.013;
    ty = (N-1) * spacing;
    plot(s.hax, [tx tx], [ty-sc ty+sc], '-', ...
        'Color',[0.3 0.3 0.3], 'LineWidth',2.5, 'HitTest','off');
    text(s.hax, tx, ty+sc*1.2, sprintf('%d µV', sc), ...
        'Color',[0.3 0.3 0.3],'FontSize',7, ...
        'HorizontalAlignment','right','HitTest','off');

    %% title
    set(s.hscale_lbl, 'String', sprintf('±%d µV', sc));
    n_bad_ch = sum(s.bad_chans);
    n_bad_ic = sum(s.bad_ics);
    n_bad_ep = size(s.bad_periods,1);
    title(s.hax, sprintf( ...
        '%s  |  %.1f – %.1f s  |  scale ±%d µV  |  bad: %d ch, %d IC, %d segment(s)', ...
        upper(s.mode), tvec(1), tvec(end), sc, n_bad_ch, n_bad_ic, n_bad_ep), ...
        'Color',[0.1 0.1 0.1],'FontSize',9,'Interpreter','none');

    %% ---- build / update topoplot panel ----------------------------------
    if strcmp(s.mode,'ica') && has_winv
        need_new = numel(s.topo_axes) ~= N || s.topo_N ~= N || ...
                   ~all(ishandle(s.topo_axes)) || ...
                   numel(s.psd_axes) ~= N || ~all(ishandle(s.psd_axes));

        if need_new
            % Delete stale topo + PSD axes
            if ~isempty(s.topo_axes)
                alive = ishandle(s.topo_axes);
                if any(alive), delete(s.topo_axes(alive)); end
            end
            if ~isempty(s.psd_axes)
                alive = ishandle(s.psd_axes);
                if any(alive), delete(s.psd_axes(alive)); end
            end

            topo_handles = gobjects(1, N);
            psd_handles  = gobjects(1, N);

            for i = 1:N
                y0_data = (N - i) * spacing;
                y_c = ax_b + ax_h * (y0_data - ybot) / (ytop - ybot);
                h_n = ax_h * spacing / (ytop - ybot);

                % Square topo axes
                sz   = min(h_n * 0.88, TOPO_W - M * 2);
                x_ax = topo_x + (TOPO_W - sz) / 2;
                y_ax = y_c - sz / 2;

                tax = axes('Parent', hfig, ...
                    'Units',    'normalized', ...
                    'Position', [x_ax, y_ax, sz, sz], ...
                    'Color',    [1 1 1], ...
                    'Tag',      sprintf('topo_%d', i));
                set(hfig, 'CurrentAxes', tax);

                if has_chanlocs && i <= size(EEG.icawinv, 2)
                    try
                        topoplot(EEG.icawinv(:,i), EEG.chanlocs, ...
                            'style','map','electrodes','off', ...
                            'shading','interp','whitebk','on');
                    catch
                        text(0.5, 0.5, '?', 'Units','normalized', ...
                            'HorizontalAlignment','center','FontSize',8);
                    end
                else
                    text(0.5, 0.5, labels{i}, 'Units','normalized', ...
                        'HorizontalAlignment','center','FontSize',7);
                end
                topo_handles(i) = tax;

                % PSD axes — same height as topo, fills PSD column
                pax = axes('Parent', hfig, ...
                    'Units',    'normalized', ...
                    'Position', [psd_x + M, y_ax, PSD_W - M*2, sz], ...
                    'Color',    [1 1 1], ...
                    'FontSize', 6, ...
                    'Tag',      sprintf('psd_%d', i));

                try
                    win_samp = min(EEG.srate * 4, floor(size(EEG.icaact, 2) / 4));
                    win_samp = max(win_samp, 64);
                    [pxx, f] = pwelch(double(EEG.icaact(i,:)), win_samp, [], [], EEG.srate);
                    fmask    = f >= 1 & f <= 40;
                    pdb      = 10*log10(pxx(fmask));
                    plot(pax, f(fmask), pdb, 'k-', 'LineWidth', 0.8);
                    set(pax, 'XLim',[1 40], ...
                        'YLim',[min(pdb)-1, max(pdb)+1], ...
                        'XTick',[10 20 30 40], 'YTick',[], ...
                        'Box','off', 'TickLength',[0.02 0], ...
                        'XColor',[0.4 0.4 0.4], 'YColor','none');
                    xlabel(pax, 'Hz', 'FontSize',6, 'Color',[0.4 0.4 0.4]);
                catch
                    text(pax, 0.5, 0.5, 'PSD n/a', 'Units','normalized', ...
                        'HorizontalAlignment','center','FontSize',6);
                    set(pax, 'XTick',[], 'YTick',[]);
                end
                psd_handles(i) = pax;
            end

            s.topo_axes = topo_handles;
            s.psd_axes  = psd_handles;
            s.topo_N    = N;
        end

        % Update border colour on topo + PSD to reflect bad/good status
        for i = 1:N
            is_bad = i <= numel(bad_arr) && bad_arr(i);
            if ishandle(s.topo_axes(i))
                if is_bad
                    set(s.topo_axes(i), 'Box','on', 'LineWidth',2.5, ...
                        'XColor',[0.85 0.10 0.10], 'YColor',[0.85 0.10 0.10], ...
                        'Color',[1 0.91 0.91]);
                else
                    set(s.topo_axes(i), 'Box','off', 'LineWidth',0.5, ...
                        'XColor',[0.8 0.8 0.8], 'YColor',[0.8 0.8 0.8], ...
                        'Color',[1 1 1]);
                end
            end
            if ishandle(s.psd_axes(i))
                if is_bad
                    set(s.psd_axes(i), 'Box','on', 'LineWidth',2.0, ...
                        'XColor',[0.85 0.10 0.10]);
                else
                    set(s.psd_axes(i), 'Box','off', ...
                        'XColor',[0.4 0.4 0.4]);
                end
            end
        end

    else
        % EEG mode: tear down any leftover topo + PSD axes
        if ~isempty(s.topo_axes)
            alive = ishandle(s.topo_axes);
            if any(alive), delete(s.topo_axes(alive)); end
            s.topo_axes = gobjects(1,0);
            s.topo_N    = 0;
        end
        if ~isempty(s.psd_axes)
            alive = ishandle(s.psd_axes);
            if any(alive), delete(s.psd_axes(alive)); end
            s.psd_axes = gobjects(1,0);
        end
    end

    setappdata(hfig, 's', s);
end % redraw

%% ==========================================================================
%  CALLBACKS
%% ==========================================================================

function scroll_cb(dir)
    s = getappdata(hfig,'s');
    s.win_start = s.win_start + dir * s.win_dur;
    setappdata(hfig,'s',s);
    redraw();
end

function scale_cb(delta)
    s = getappdata(hfig,'s');
    if strcmp(s.mode,'ica')
        s.scale_ica = max(5, s.scale_ica + delta);
    else
        s.scale_eeg = max(5, s.scale_eeg + delta);
    end
    setappdata(hfig,'s',s);
    redraw();
end

function toggle_cb(~,~)
    s = getappdata(hfig,'s');
    if strcmp(s.mode,'eeg')
        if ~(isfield(s.EEG,'icaact') && ~isempty(s.EEG.icaact))
            warndlg('EEG.icaact is empty or missing.','No ICA'); return;
        end
        s.mode = 'ica';
        set(s.htoggle,'String','Show EEG');
    else
        s.mode = 'eeg';
        set(s.htoggle,'String','Show ICA');
    end
    setappdata(hfig,'s',s);
    redraw();
end

function chan_click_cb(~, ~, idx)
    s = getappdata(hfig,'s');
    if strcmp(s.mode,'eeg')
        if idx <= numel(s.bad_chans)
            s.bad_chans(idx) = ~s.bad_chans(idx);
        end
    else
        if idx <= numel(s.bad_ics)
            s.bad_ics(idx) = ~s.bad_ics(idx);
        end
    end
    setappdata(hfig,'s',s);
    redraw();
end

function ax_click_cb(~, ~)
    s  = getappdata(hfig,'s');
    cp = get(s.hax, 'CurrentPoint');
    cx = cp(1,1);

    mods       = get(hfig,'CurrentModifier');
    shift_held = any(strcmpi(mods,'shift'));

    nsamp    = size(s.EEG.data, 2);
    cx_samp  = max(1, min(nsamp, round(cx * s.EEG.srate) + 1));

    if shift_held && ~isnan(s.click_time)
        % ---- complete a bad-period mark ----------------------------------
        t1    = min(s.click_time, cx);
        t2    = max(s.click_time, cx);
        samp1 = max(1,     round(t1 * s.EEG.srate) + 1);
        samp2 = min(nsamp, round(t2 * s.EEG.srate) + 1);
        if samp2 > samp1
            s.bad_periods = merge_periods([s.bad_periods; samp1, samp2]);
        end
        s.click_time = NaN;

    else
        % ---- plain click: undo region if hit, otherwise set marker -------
        hit = find( cx_samp >= s.bad_periods(:,1) & ...
                    cx_samp <= s.bad_periods(:,2), 1);
        if ~isempty(hit)
            s.bad_periods(hit, :) = [];   % remove the clicked region
            s.click_time = NaN;           % also clear any pending marker
        else
            s.click_time = cx;
        end
    end

    setappdata(hfig,'s',s);
    redraw();
end

function periods = merge_periods(periods)
    % Merge any overlapping or adjacent [start, end] sample rows.
    if size(periods, 1) < 2, return; end
    periods = sortrows(periods, 1);
    out = periods(1, :);
    for k = 2:size(periods, 1)
        if periods(k,1) <= out(end,2) + 1   % overlapping or touching
            out(end,2) = max(out(end,2), periods(k,2));
        else
            out = [out; periods(k,:)];       %#ok<AGROW>
        end
    end
    periods = out;
end

function key_cb(~, evt)
    switch evt.Key
        case 'leftarrow',  scroll_cb(-1);
        case 'rightarrow', scroll_cb(+1);
        case 'uparrow',    scale_cb(-10);
        case 'downarrow',  scale_cb(+10);
    end
end

function reject_cb(~, ~)
    s   = getappdata(hfig,'s');
    EEG = s.EEG;
    changed = false;

    %% 1. Subtract bad ICA components
    bad_ic_idx = find(s.bad_ics);
    if ~isempty(bad_ic_idx)
        try
            EEG = pop_subcomp(EEG, bad_ic_idx, 0);
            fprintf('[reviewwindow] Subtracted ICs: %s\n', mat2str(bad_ic_idx));
            if ~isempty(EEG.icaweights)
                EEG.icaact = (EEG.icaweights * EEG.icasphere) * ...
                              EEG.data(EEG.icachansind, :);
            end
            s.bad_ics = false(1, 0);
            changed   = true;
        catch e
            warndlg(['pop_subcomp: ' e.message], 'IC Rejection Error');
        end
    end

    %% 2. Remove bad channels
    bad_ch_idx = find(s.bad_chans);
    if ~isempty(bad_ch_idx)
        try
            EEG = pop_select(EEG, 'nochannel', bad_ch_idx);
            fprintf('[reviewwindow] Removed channels: %s\n', mat2str(bad_ch_idx));
            s.bad_chans = false(1, size(EEG.data, 1));
            changed = true;
        catch e
            warndlg(['pop_select: ' e.message], 'Channel Rejection Error');
        end
    end

    %% 3. Reject bad time segments
    if ~isempty(s.bad_periods)
        try
            EEG = eeg_eegrej(EEG, s.bad_periods);
            fprintf('[reviewwindow] Removed %d time segment(s)\n', ...
                size(s.bad_periods,1));
            s.bad_periods = zeros(0,2);
            changed = true;
        catch e
            warndlg(['eeg_eegrej: ' e.message], 'Time Rejection Error');
        end
    end

    % Nothing marked as bad — return original EEG unchanged.
    % (no alert; just fall through and close)

    try, EEG = eeg_checkset(EEG); catch, end

    % Clear topo + PSD axes before rebuild
    if ~isempty(s.topo_axes)
        alive = ishandle(s.topo_axes);
        if any(alive), delete(s.topo_axes(alive)); end
    end
    if ~isempty(s.psd_axes)
        alive = ishandle(s.psd_axes);
        if any(alive), delete(s.psd_axes(alive)); end
    end

    s.EEG       = EEG;
    s.bad_chans = false(1, size(EEG.data, 1));
    s.topo_axes = gobjects(1,0);
    s.psd_axes  = gobjects(1,0);
    s.topo_N    = 0;
    if isfield(EEG,'icaact') && ~isempty(EEG.icaact)
        s.bad_ics = false(1, size(EEG.icaact,1));
        set(s.htoggle,'Enable','on');
    else
        s.bad_ics = false(1,0);
        set(s.htoggle,'Enable','off','String','No ICA');
    end
    s.win_start  = 0;
    s.click_time = NaN;

    s.out_EEG = EEG;
    setappdata(hfig,'s',s);
    assignin('base','EEG', EEG);
    uiresume(hfig);   % unblocks uiwait; post-wait code will close the figure
end % reject_cb

function run_ica_cb(~, ~)
    s   = getappdata(hfig,'s');
    EEG = s.EEG;

    set(hrun_ica, 'Enable','off', 'String','Running ICA…');
    drawnow;

    new_EEG  = [];
    method   = '';

    % --- PCA reduction for high-density arrays ----------------------------
    % For n > 40 channels: n_pca = 40 + floor((n-40)/2)
    %   60 ch  → 50 components,  128 ch → 84 components
    n_ch = size(EEG.data, 1);
    if n_ch > 40
        n_pca    = 40 + floor((n_ch - 40) / 2);
        pca_args = {'pca', n_pca};
        fprintf('[reviewwindow] %d channels → PCA to %d components\n', n_ch, n_pca);
    else
        pca_args = {};
    end

    % --- try binica first -------------------------------------------------
    try
        fprintf('[reviewwindow] Running ICA: binica …\n');
        new_EEG = pop_runica(EEG, 'icatype','binica', pca_args{:});
        method  = 'binica';
    catch e_binica
        fprintf('[reviewwindow] binica failed (%s), trying runica extended…\n', ...
            e_binica.message);
        % --- fall back to runica with extended option --------------------
        try
            new_EEG = pop_runica(EEG, 'icatype','runica', 'extended',1, pca_args{:});
            method  = 'runica (extended)';
        catch e_runica
            warndlg( ...
                sprintf('ICA failed with both methods.\nrunica error: %s', ...
                        e_runica.message), ...
                'ICA Error');
        end
    end

    set(hrun_ica, 'Enable','on', 'String','Run ICA');

    if isempty(new_EEG), return; end

    fprintf('[reviewwindow] ICA complete using %s.\n', method);

    % Ensure activations are computed
    try
        new_EEG = eeg_checkset(new_EEG, 'ica');
    catch
        try
            new_EEG.icaact = (new_EEG.icaweights * new_EEG.icasphere) * ...
                              new_EEG.data(new_EEG.icachansind, :);
        catch
        end
    end

    % Tear down any existing topo + PSD axes (belong to old decomposition)
    if ~isempty(s.topo_axes)
        alive = ishandle(s.topo_axes);
        if any(alive), delete(s.topo_axes(alive)); end
    end
    if ~isempty(s.psd_axes)
        alive = ishandle(s.psd_axes);
        if any(alive), delete(s.psd_axes(alive)); end
    end

    s.EEG       = new_EEG;
    s.bad_ics   = false(1, size(new_EEG.icawinv, 2));
    s.topo_axes = gobjects(1,0);
    s.psd_axes  = gobjects(1,0);
    s.topo_N    = 0;

    set(s.htoggle, 'Enable','on', 'String','Show ICA');

    setappdata(hfig,'s',s);
    assignin('base','EEG', new_EEG);
    fprintf('[reviewwindow] ICA complete (%s). EEG saved to workspace.\n', method);
    redraw();
end % run_ica_cb

function close_req_cb(~, ~)
    % Called when the user clicks the window's X button.
    % Don't delete the figure here — just release uiwait so the
    % post-wait block can read state and then delete it cleanly.
    uiresume(hfig);
end % close_req_cb

end % reviewwindow
