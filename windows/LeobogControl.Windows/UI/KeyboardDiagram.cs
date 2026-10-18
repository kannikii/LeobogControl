using System.Drawing.Drawing2D;
using LeobogControl.Core;

namespace LeobogControl.UI;

/// Hi8SE 배열표를 그려 주는 컨트롤. 눌린 키·매핑된 키·선택 키·강조 키를 색으로 표시하고, 클릭하면 KeyClicked 를 올린다.
public sealed class KeyboardDiagram : Control
{
    IReadOnlyList<PhysicalKey> _keys = Hi8SELayout.Keys(KeyboardMode.Windows);
    public IReadOnlyList<PhysicalKey> Keys { get => _keys; set { _keys = value; Invalidate(); } }
    public HashSet<int> Pressed { get; } = new();
    public Dictionary<int, string> Remapped { get; } = new();
    public HashSet<int> Highlight { get; } = new();
    int? _selected;
    public int? Selected { get => _selected; set { _selected = value; Invalidate(); } }
    public bool Clickable { get; set; } = true;
    public event Action<PhysicalKey>? KeyClicked;

    public KeyboardDiagram()
    {
        DoubleBuffered = true;
        SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.UserPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true);
        BackColor = Color.FromArgb(246, 247, 249);
        MinimumSize = new Size(331, 134);
    }

    (float Scale, float OffX, float OffY) Transform()
    {
        var pad = 6f;
        var s = Math.Min((Width - pad * 2) / Hi8SELayout.CanvasSize.Width, (Height - pad * 2) / Hi8SELayout.CanvasSize.Height);
        if (s <= 0) s = 0.1f;
        var ox = (Width - Hi8SELayout.CanvasSize.Width * s) / 2f;
        var oy = (Height - Hi8SELayout.CanvasSize.Height * s) / 2f;
        return (s, ox, oy);
    }

    RectangleF Rect(PhysicalKey k, (float Scale, float OffX, float OffY) t) =>
        new(t.OffX + k.Frame.X * t.Scale, t.OffY + k.Frame.Y * t.Scale, k.Frame.Width * t.Scale, k.Frame.Height * t.Scale);

    protected override void OnPaint(PaintEventArgs e)
    {
        base.OnPaint(e);
        var g = e.Graphics;
        g.SmoothingMode = SmoothingMode.AntiAlias;
        g.TextRenderingHint = System.Drawing.Text.TextRenderingHint.ClearTypeGridFit;
        var t = Transform();
        using var font = new Font(Font.FontFamily, Math.Max(6f, 8f * t.Scale), FontStyle.Regular);
        using var small = new Font(Font.FontFamily, Math.Max(5.5f, 6.5f * t.Scale), FontStyle.Bold);
        var fmt = new StringFormat { Alignment = StringAlignment.Center, LineAlignment = StringAlignment.Center, Trimming = StringTrimming.None, FormatFlags = StringFormatFlags.NoWrap };
        foreach (var k in _keys)
        {
            var r = Rect(k, t);
            r.Inflate(-1.2f * t.Scale, -1.2f * t.Scale);
            Color fill, border = Color.FromArgb(190, 194, 200), text = Color.FromArgb(40, 40, 46);
            if (Pressed.Contains(k.Id)) { fill = Color.FromArgb(52, 120, 246); text = Color.White; border = fill; }
            else if (_selected == k.Id) { fill = Color.FromArgb(255, 221, 150); border = Color.FromArgb(220, 150, 20); }
            else if (Remapped.ContainsKey(k.Id)) { fill = Color.FromArgb(255, 236, 200); border = Color.FromArgb(230, 160, 40); }
            else if (Highlight.Contains(k.Id)) { fill = Color.FromArgb(214, 236, 214); border = Color.FromArgb(70, 150, 90); }
            else if (k.Kind == KeyKind.Knob) { fill = Color.FromArgb(70, 74, 84); text = Color.White; }
            else if (k.Kind == KeyKind.Fn) { fill = Color.FromArgb(226, 228, 234); }
            else fill = Color.White;

            using var path = Rounded(r, Math.Max(2f, 4f * t.Scale));
            using (var b = new SolidBrush(fill)) g.FillPath(b, path);
            using (var p = new Pen(border, 1f)) g.DrawPath(p, path);
            using var tb = new SolidBrush(text);
            if (Remapped.TryGetValue(k.Id, out var mapped))
            {
                var top = new RectangleF(r.X, r.Y, r.Width, r.Height * 0.5f);
                var bottom = new RectangleF(r.X, r.Y + r.Height * 0.45f, r.Width, r.Height * 0.55f);
                using var dim = new SolidBrush(Color.FromArgb(140, 110, 60));
                g.DrawString(k.DisplayLabel, small, dim, top, fmt);
                g.DrawString(mapped, font, tb, bottom, fmt);
            }
            else g.DrawString(k.DisplayLabel, font, tb, r, fmt);
        }
    }

    static GraphicsPath Rounded(RectangleF r, float rad)
    {
        var p = new GraphicsPath();
        var d = rad * 2;
        p.AddArc(r.X, r.Y, d, d, 180, 90);
        p.AddArc(r.Right - d, r.Y, d, d, 270, 90);
        p.AddArc(r.Right - d, r.Bottom - d, d, d, 0, 90);
        p.AddArc(r.X, r.Bottom - d, d, d, 90, 90);
        p.CloseFigure();
        return p;
    }

    public PhysicalKey? HitTest(Point pt)
    {
        var t = Transform();
        return _keys.FirstOrDefault(k => Rect(k, t).Contains(pt));
    }

    protected override void OnMouseClick(MouseEventArgs e)
    {
        base.OnMouseClick(e);
        if (!Clickable || e.Button != MouseButtons.Left) return;
        var k = HitTest(e.Location);
        if (k is not null) KeyClicked?.Invoke(k);
    }

    protected override void OnMouseMove(MouseEventArgs e)
    {
        base.OnMouseMove(e);
        Cursor = Clickable && HitTest(e.Location) is not null ? Cursors.Hand : Cursors.Default;
    }
}
