#include "widget.h"
void PaintWidget( ui::Widget& w )
{
    w.Draw();
}
void PaintGadget( ui::Gadget& g )
{
    g.Draw();
}
void RefreshCanvas( ui::Canvas& c )
{
    c.Repaint();
}
